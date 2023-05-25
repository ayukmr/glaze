module Glaze
  # llvm internals
  class Llvm
    # create llvm internals
    def initialize
      @module  = create_module
      @vars    = {}
      @globals = {}
      @funcs   = {}

      # current function
      @func  = nil
      @block = nil

      # print function
      @printf =
        @module.functions.add(
          'printf',
          LLVM.Function(
            [LLVM.Pointer(LLVM::Int8)],
            LLVM::Int,
            varargs: true
          )
        )

      # list functions
      @list_length =
        @module.functions.add(
          'listLength',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE)],
          LLVM::Int
        )

      @list_create =
        @module.functions.add(
          'listCreate',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE)],
          LLVM.Void
        )

      @list_range =
        @module.functions.add(
          'listRange',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM::Int, LLVM::Int],
          LLVM.Void
        )

      @list_value =
        @module.functions.add(
          'listValue',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM::Int],
          LLVM.Pointer(LLVM::Int8)
        )

      @list_set =
        @module.functions.add(
          'listSet',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM::Int, LLVM.Pointer(LLVM::Int8)],
          LLVM.Void
        )

      @list_prepend =
        @module.functions.add(
          'listPrepend',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM.Pointer(LLVM::Int8)],
          LLVM.Void
        )

      @list_append =
        @module.functions.add(
          'listAppend',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM.Pointer(LLVM::Int8)],
          LLVM.Void
        )

      @list_delete =
        @module.functions.add(
          'listDelete',
          [LLVM.Pointer(Glaze::Constants::LIST_TYPE), LLVM::Int],
          LLVM.Void
        )
    end

    # raise building error
    def error(message)
      raise_error('building', message)
    end

    # create llvm module
    def create_module
      @module = LLVM::Module.new('glaze')
    end

    # compile llvm module
    def compile_module(debug: false, file: false)
      print_module if debug

      # require main function
      error 'main function must be defined' unless @funcs['main']
      error 'main function must return integer' \
        unless @funcs['main'].function_type.return_type == LLVM::Int

      # lists llvm file
      lists_module = LLVM::Module.parse_bitcode(
        File.expand_path('../../build/lists.bc', __dir__)
      )

      lists_module.link_into(@module)

      # compile ir
      if file
        @module.write_bitcode(file)
      else
        # initialize jit
        LLVM.init_jit

        engine = LLVM::JITCompiler.new(@module)
        engine.run_function(@funcs['main'])

        engine.dispose
      end
    end

    # print module
    def print_module
      puts @module

      puts
      puts '——————————'
      puts
    end

    # create function
    def create_function(name, param_hashes, type)
      # parameter types and names
      param_types = param_hashes.map { |param| param[:type] }

      @func  = @module.functions.add(name, param_types, type)
      @block = @func.basic_blocks.append

      @vars[@func] = {}
      @funcs[name] = @func

      # create variables for parameters
      params = @func.params
      param_hashes.each_with_index do |param, index|
        create_variable(param[:name], param[:type], params[index])
      end
    end

    # call function
    def call_function(name, params)
      func = @funcs[name]

      # error on undefined function
      error "undefined function `#{name}`" unless func

      @block.build do |builder|
        return params.empty? ? builder.call(func) : builder.call(func, *params)
      end
    end

    # start if statement
    def start_if(bool)
      blk_true = @func.basic_blocks.append
      blk_else = @func.basic_blocks.append
      blk_exit = @func.basic_blocks.append

      @block.build do |builder|
        # branch to true or exit
        builder.cond(bool, blk_true, blk_else)
      end

      @block = blk_true
      [blk_true, blk_else, blk_exit]
    end

    # start else block
    def start_else(blk_else)
      @block = blk_else
    end

    # end if statement
    def end_if(blk_true, blk_else, blk_exit)
      blk_true.build do |builder|
        builder.br(blk_exit)
      end

      blk_else.build do |builder|
        builder.br(blk_exit)
      end

      @block = blk_exit
    end

    # start for loop
    def start_for(var, type, list)
      blk_body = @func.basic_blocks.append

      list_ptr = nil

      index    = nil
      idx_next = nil

      @block.build do |builder|
        list_ptr = builder.alloca(Glaze::Constants::LIST_TYPE)
        builder.store(list, list_ptr)

        # store next index
        idx_next = builder.alloca(LLVM::Int)
        builder.store(LLVM.Int(0), idx_next)

        builder.br(blk_body)
      end

      blk_body.build do |builder|
        index = builder.alloca(LLVM::Int)
        builder.store(builder.load(idx_next), index)

        # set variable to list element
        pointer = builder.alloca(type)
        value   = builder.call(@list_value, list_ptr, builder.load(index))

        builder.store(builder.bit_cast(value, type), pointer)
        set_pointer(var, pointer)

        # store new next index
        idx_new = builder.add(builder.load(index), LLVM.Int(1))
        builder.store(idx_new, idx_next)
      end

      @block = blk_body
      [idx_next, blk_body]
    end

    # end for loop
    def end_for(end_num, idx_next, blk_body)
      blk_exit = @func.basic_blocks.append

      @block.build do |builder|
        # compare next index to end number
        bool = builder.icmp(:slt, builder.load(idx_next), end_num)

        # branch to body or exit
        builder.cond(bool, blk_body, blk_exit)
      end

      @block = blk_exit
    end

    # set pointer in hash
    def set_pointer(name, pointer)
      @vars[@func][name] = pointer
    end

    # get pointer from hash
    def get_pointer(name)
      pointer = @vars[@func][name]
      error "undefined variable `#{name}`" unless pointer

      pointer
    end

    # delete pointer in hash
    def delete_pointer(name)
      pointer = @vars[@func][name]
      error "undefined variable `#{name}`" unless pointer

      @vars[@func].delete(name)
    end

    # cast pointer
    def cast_pointer(pointer, type)
      @block.build do |builder|
        return builder.bit_cast(pointer, LLVM.Pointer(type))
      end
    end

    # create variable
    def create_variable(name, type, value)
      define_variable(name, type)
      set_variable(name, value)
    end

    # define variable
    def define_variable(name, type)
      @block.build do |builder|
        pointer = builder.alloca(type)
        set_pointer(name, pointer)
      end
    end

    # set value of variable
    def set_variable(name, value)
      pointer = get_pointer(name)

      error 'variable type does not match value' \
        unless LLVM.Pointer(value.type) == pointer.type

      @block.build do |builder|
        builder.store(value, pointer)
      end
    end

    # get value of variable
    def load_variable(name)
      var = get_pointer(name)

      @block.build do |builder|
        return builder.load(var)
      end
    end

    # boolean negation operator
    def bool_not(bool)
      error 'cannot negate non-boolean values' \
        unless bool.type.kind == :integer

      @block.build do |builder|
        return builder.not(bool)
      end
    end

    # boolean or operator
    def bool_or(lhs, rhs)
      error 'cannot compare non-boolean values' \
        unless lhs.type.kind == :integer && rhs.type.kind == :integer

      @block.build do |builder|
        return builder.or(lhs, rhs)
      end
    end

    # boolean and operator
    def bool_and(lhs, rhs)
      error 'cannot compare non-boolean values' \
        unless lhs.type.kind == :integer && rhs.type.kind == :integer

      @block.build do |builder|
        return builder.and(lhs, rhs)
      end
    end

    # comparison operations
    def cmp_operation(oprt, lhs, rhs)
      error 'cannot compare non-int values' \
        unless lhs.type.kind == :integer && rhs.type.kind == :integer

      pred = {
        # equal to
        '==': :eq,
        '!=': :ne,

        # less than
        '<':  :slt,
        '<=': :sle,

        # greater than
        '>':  :sgt,
        '>=': :sge
      }[oprt.to_sym]

      @block.build do |builder|
        return builder.icmp(pred, lhs, rhs)
      end
    end

    # integer operations
    def int_operation(lhs, rhs, oprt)
      error 'cannot operate on non-int values' \
        unless lhs.type.kind == :integer && rhs.type.kind == :integer

      @block.build do |builder|
        return \
          case oprt
          # add integers
          when '+'
            builder.add(lhs, rhs)

          # subtract integers
          when '-'
            builder.sub(lhs, rhs)

          # multiply integers
          when '*'
            builder.mul(lhs, rhs)

          # divide integers
          when '/'
            builder.sdiv(lhs, rhs)
          end
      end
    end

    # create and load global string
    def global_string(text)
      @block.build do |builder|
        global = builder.global_string(text)

        # load global string
        zero = LLVM.Int(0)
        return builder.gep2(LLVM::Int8, global, [zero, zero], '')
      end
    end

    # create list
    def list_create(values)
      @block.build do |builder|
        pointer = builder.alloca(Glaze::Constants::LIST_TYPE)
        builder.call(@list_create, pointer)

        # append values
        values.each do |value|
          builder.call(@list_append, pointer, value)
        end

        return builder.load(pointer)
      end
    end

    # create list from range
    def list_range(start_num, end_num)
      @block.build do |builder|
        pointer = builder.alloca(Glaze::Constants::LIST_TYPE)
        builder.call(@list_range, pointer, start_num, end_num)

        return builder.load(pointer)
      end
    end

    # get length of list
    def list_length(list)
      @block.build do |builder|
        pointer = builder.alloca(Glaze::Constants::LIST_TYPE)
        builder.store(list, pointer)

        return builder.call(@list_length, pointer)
      end
    end

    # get element from list
    def list_index(list, index)
      @block.build do |builder|
        pointer = builder.alloca(Glaze::Constants::LIST_TYPE)
        builder.store(list, pointer)

        return builder.call(@list_value, pointer, index)
      end
    end

    # set element in list
    def list_set(pointer, index, value)
      @block.build do |builder|
        builder.call(@list_set, pointer, index, value)
      end
    end

    # prepend element to list
    def list_prepend(pointer, value)
      @block.build do |builder|
        builder.call(@list_prepend, pointer, value)
      end
    end

    # append element to list
    def list_append(pointer, value)
      @block.build do |builder|
        builder.call(@list_append, pointer, value)
      end
    end

    # delete element in list
    def list_delete(pointer, index)
      @block.build do |builder|
        builder.call(@list_delete, pointer, index)
      end
    end

    # print string
    def printf(format_string, values)
      format = global_string(format_string)

      @block.build do |builder|
        if values.empty?
          # print format string
          builder.call(@printf, format)
        else
          # print with values
          builder.call(@printf, format, *values)
        end
      end
    end

    # return value from function
    def return(value)
      error 'illegal return value' \
        unless (!value && @func.function_type.return_type == LLVM.Void) ||
               (value && value.type == @func.function_type.return_type)

      @block.build do |builder|
        # return value
        builder.ret(value)
      end
    end
  end
end
