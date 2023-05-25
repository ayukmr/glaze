# llvm bindings
require 'llvm/core'
require 'llvm/linker'
require 'llvm/execution_engine'

# lexing and parsing
require 'rly'
require 'english'

# glaze modules
module Glaze
end

# glaze library
require 'glaze/utils'
require 'glaze/constants'
require 'glaze/llvm'
require 'glaze/lexer'
require 'glaze/parser'
require 'glaze/compiler'
