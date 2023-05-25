module Glaze
  # lexer for compiler
  class Lexer < Rly::Lex
    # raise lexing error
    def self.error(message)
      raise_error('lexing', message)
    end

    keywords = %w[println delete return elsif print else func end for let if in]

    literals '+-*/!,:=()[]'
    ignore " \t\n"

    # tokenize types
    token :TYPE, /int|bool|string|list/ do |token|
      types = {
        int:    LLVM::Int,
        bool:   LLVM::Int1,
        string: LLVM.Pointer(LLVM::Int8),
        list:   Glaze::Constants::LIST_TYPE
      }

      token.value = types[token.value.to_sym]
      token
    end

    # tokenize keywords
    keywords.each do |keyword|
      token keyword.upcase.to_sym, keyword
    end

    # tokenize strings
    token :STRING, /"[^"]*"/ do |token|
      token.value = token.value[1...-1].gsub('\n', "\n")
      token
    end

    # tokenize numbers
    token :NUMBER, /[+-]?\d+/ do |token|
      token.value = token.value.to_i
      token
    end

    # range symbols
    token :RANGE,   /\.\./
    token :RANGEEQ, /\.\.=/

    # list symbols
    token :PREPEND, />>/
    token :APPEND,  /<</

    # boolean operators
    token :OR,  /\|\|/
    token :AND, /&&/

    # symbols
    token :ARROW, /->/

    # comparisons
    token :CMP, /==|!=|<=|<|>=|>/

    # operators
    token :OPRT, %r{(\+|-|\*|/)=}

    # identifiers
    token :IDENT, /[a-zA-Z_]\w*/

    # comments
    token :COMMENT, /#[^\n]*/

    # error on illegal character
    on_error do |token|
      error "illegal character `#{token.value}`"
    end
  end
end
