module Glaze
  # parser for compiler
  class Parser < Rly::Yacc
    # create parser
    def initialize(lexer)
      @llvm = Glaze::Llvm.new
      @closings = []

      super lexer
    end

    # raise parsing error
    def error(message)
      raise_error('parsing', message)
    end

    # compile llvm module
    def compile_module
      @llvm.compile_module
    end

    # require function for statement
    def require_func
      error 'cannot use statements in global context' \
        unless @closings.find { |closing| closing[:type] == :function }
    end

    # operator precedence
    precedence :left, '+', '-'
    precedence :left, '*', '/'

    # multiple statements
    rule 'statements : statement | statements statement | ', &proc {}

    # comments
    rule 'statement : COMMENT', &proc {}

    # expression with parentheses
    rule 'expression : "(" expression ")"' do |expr, _, inside|
      expr.value = inside.value
    end

    # create number
    rule 'expression : NUMBER' do |expr, num|
      expr.value = LLVM.Int(num.value)
    end

    # create string
    rule 'expression : STRING' do |expr, str|
      expr.value = @llvm.global_string(str.value)
    end

    # get variable
    rule 'expression : IDENT' do |expr, name|
      expr.value = @llvm.load_variable(name.value)
    end

    # cast pointer
    rule 'expression : expression ":" TYPE' do |expr, pointer, _, type|
      expr.value = @llvm.cast_pointer(pointer.value, type.value)
    end

    # create list
    rule 'expression : "[" expressions "]"' do |expr, _, exprs|
      expr.value = @llvm.list_create(exprs.value)
    end

    # get element from list
    rule 'expression : expression "[" expression "]"' do |expr, list, _, index|
      expr.value = @llvm.list_index(list.value, index.value)
    end

    # create list from range
    rule 'expression : expression RANGE expression' do |expr, start_num, _, end_num|
      expr.value = @llvm.list_range(start_num.value, end_num.value)
    end

    # create list from range
    rule 'expression : expression RANGEEQ expression' do |expr, start_num, _, end_num|
      expr.value = @llvm.list_range(
        start_num.value,
        @llvm.int_operation(end_num.value, LLVM.Int(1), '+')
      )
    end

    # boolean negation operator
    rule 'expression : "!" expression' do |expr, _, bool|
      expr.value = @llvm.bool_negate(bool.value)
    end

    # boolean or operator
    rule 'expression : expression OR expression' do |expr, lhs, _, rhs|
      expr.value = @llvm.bool_or(lhs.value, rhs.value)
    end

    # boolean and operator
    rule 'expression : expression AND expression' do |expr, lhs, _, rhs|
      expr.value = @llvm.bool_and(lhs.value, rhs.value)
    end

    # comparison operations
    rule 'expression : expression CMP expression' do |expr, lhs, oprt, rhs|
      expr.value = @llvm.cmp_operation(oprt.value, lhs.value, rhs.value)
    end

    # integer operations
    rule 'expression : expression "+" expression
                     | expression "-" expression
                     | expression "*" expression
                     | expression "/" expression' do |expr, lhs, oprt, rhs|
      expr.value = @llvm.int_operation(lhs.value, rhs.value, oprt.value)
    end

    # call function
    rule 'expression : IDENT "(" expressions ")"' do |expr, func, _, params|
      expr.value = @llvm.call_function(func.value, params.value)
    end

    # zero or more expressions
    rule 'expressions : expression | expressions_comma | ' do |exprs, raw_exprs|
      exprs.value =
        if !raw_exprs
          # no params
          []
        elsif raw_exprs.value.is_a?(Array)
          # multiple params
          raw_exprs.value
        else
          # single param
          [raw_exprs.value]
        end
    end

    # expressions with commas
    rule 'expressions_comma : expressions "," expression' do |exprs_comma, exprs, _, expr|
      exprs_comma.value = exprs.value << expr.value
    end

    # define function
    rule 'statement : FUNC IDENT "(" params ")" return_type' do |*args|
      error 'cannot define function inside function' \
        if @closings.find { |closing| closing[:type] == :function }

      _, _, name, _, params, _, ret_type = args

      # create function
      @llvm.create_function(name.value, params.value, ret_type.value)
      @closings.push({ type: :function, state: { returned: false } })
    end

    # function return type
    rule 'return_type : arrow_type | void' do |ret_type, type|
      ret_type.value = type.value
    end

    # arrow and type
    rule 'arrow_type : ARROW TYPE' do |ret_type, _, type|
      ret_type.value = type.value
    end

    # void type
    rule 'void : ' do |void|
      void.value = LLVM.Void
    end

    # one or more parameters
    rule 'params : param | params_comma | ' do |params, raw_params|
      params.value =
        if !raw_params
          # no params
          []
        elsif raw_params.value.is_a?(Array)
          # multiple params
          raw_params.value
        else
          # single param
          [raw_params.value]
        end
    end

    # parameters with commas
    rule 'params_comma : params "," param' do |params_comma, params, _, param|
      params_comma.value = params.value << param.value
    end

    # parameter for function
    rule 'param : TYPE IDENT' do |param, type, name|
      param.value = { type: type.value, name: name.value }
    end

    # start if statement
    rule 'statement : IF expression' do |_, _, bool|
      require_func
      blk_true, blk_else, blk_exit = @llvm.start_if(bool.value)

      # add if statement to closings
      @closings.push(
        {
          type: :if,
          state: {
            blk_true:,
            blk_else:,
            blk_exit:
          }
        }
      )
    end

    # add else statement
    rule 'statement : ELSE' do
      require_func

      # find if statement for else block
      if_closing = @closings.reverse.find { |closing| closing[:type] == :if }
      error 'cannot use else without if' unless if_closing

      # start else
      @llvm.start_else(if_closing[:state][:blk_else])
    end

    # start for loop
    rule 'statement : FOR IDENT ":" TYPE IN expression' do |*args|
      require_func

      _, _, var, _, type, _, list = args
      idx_next, blk_body = @llvm.start_for(var.value, type.value, list.value)

      # add for loop to closings
      @closings.push(
        {
          type: :for,
          state: {
            end_num: @llvm.list_length(list.value),
            idx_next:,
            blk_body:
          }
        }
      )
    end

    # close blocks
    rule 'statement : END' do
      require_func
      closing = @closings.pop

      case closing[:type]
      # close function
      when :function
        error 'have to return from function' \
          unless closing[:state][:returned]

      # close if statement
      when :if
        @llvm.end_if(
          closing[:state][:blk_true],
          closing[:state][:blk_else],
          closing[:state][:blk_exit]
        )

      # close for loop
      when :for
        @llvm.end_for(
          closing[:state][:end_num],
          closing[:state][:idx_next],
          closing[:state][:blk_body]
        )

      # error on illegal use
      else
        error 'illegal use of `end`'
      end
    end

    # define variable
    rule 'statement : TYPE IDENT' do |_, type, name|
      require_func
      @llvm.define_variable(name.value, type.value)
    end

    # create variable
    rule 'statement : TYPE IDENT "=" expression' do |_, type, name, _, expr|
      require_func
      @llvm.create_variable(name.value, type.value, expr.value)
    end

    # set value of variable
    rule 'statement : IDENT "=" expression' do |_, name, _, expr|
      require_func
      @llvm.set_variable(name.value, expr.value)
    end

    # variable integer operations
    rule 'statement : IDENT OPRT expression' do |_, var, oprt, rhs|
      require_func

      value =
        @llvm.int_operation(
          @llvm.load_variable(var.value),
          rhs.value,
          oprt.value[0]
        )

      @llvm.set_variable(var.value, value)
    end

    # set element in list
    rule 'statement : IDENT "[" expression "]" "=" expression' do |*args|
      require_func

      _, var, _, index, _, _, expr = args

      pointer = @llvm.get_pointer(var.value)
      @llvm.list_set(pointer, index.value, expr.value)
    end

    # delete variable
    rule 'statement : DELETE IDENT' do |_, _, var|
      require_func
      @llvm.delete_pointer(var.value)
    end

    # delete list element
    rule 'statement : DELETE IDENT "[" expression "]"' do |_, _, var, _, index|
      require_func

      pointer = @llvm.get_pointer(var.value)
      @llvm.list_delete(pointer, index.value)
    end

    # prepend element to list
    rule 'statement : IDENT PREPEND expression' do |_, var, _, expr|
      require_func

      pointer = @llvm.get_pointer(var.value)
      @llvm.list_prepend(pointer, expr.value)
    end

    # push element to list
    rule 'statement : IDENT APPEND expression' do |_, var, _, expr|
      require_func

      pointer = @llvm.get_pointer(var.value)
      @llvm.list_append(pointer, expr.value)
    end

    # call function
    rule 'statement : IDENT "(" expressions ")"' do |_, func, _, params|
      require_func
      @llvm.call_function(func.value, params.value)
    end

    # return expression
    rule 'statement : RETURN return_value' do |_, _, expr|
      require_func

      @llvm.return(expr.value)
      @closings[0][:state][:returned] = true
    end

    # return value
    rule 'return_value : expression | ' do |ret_val, val|
      ret_val.value = val.value if val
    end

    # print using printf params
    rule 'statement : PRINT printf_params' do |_, _, params|
      require_func

      str, *exprs = params.value
      @llvm.printf(str, exprs)
    end

    # print using printf params
    rule 'statement : PRINTLN printf_params' do |_, _, params|
      require_func

      str, *exprs = params.value
      @llvm.printf("#{str}\n", exprs)
    end

    # params for printf
    rule 'printf_params : STRING | printf_expression_params' do |params, raw_params|
      params.value =
        if raw_params.value.is_a?(Array)
          # multiple params
          raw_params.value
        else
          # single param
          [raw_params.value]
        end
    end

    # string and expressions params for printf
    rule 'printf_expression_params : STRING "," expressions' do |params, str, _, exprs|
      params.value = [str.value, *exprs.value]
    end

    # error on illegal token
    on_error proc { |token|
      error "error near `#{token}`"
    }
  end
end
