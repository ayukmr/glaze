module Glaze
  # constants
  module Constants
    # list nodes
    NODE_TYPE = LLVM.Struct('Node')

    # linked list
    LIST_TYPE =
      LLVM.Struct(
        LLVM::Int,
        LLVM::Int,
        LLVM.Pointer(NODE_TYPE),
        LLVM.Pointer(NODE_TYPE),
        'List'
      )
  end
end
