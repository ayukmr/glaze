module Glaze
  # compiler endpoint
  module Compiler
    class << self
      # compile source code
      def compile_source(source)
        lexer  = Glaze::Lexer.new
        parser = Glaze::Parser.new(lexer)

        # parse and compile module
        parser.parse(source)
        parser.compile_module
      end

      # compile file
      def compile_file(file)
        source = File.read(file)
        compile_source(source)
      end
    end
  end
end
