/// JibJab C Transpiler - Converts JJ to C
/// Uses shared C-family base from CFamilyTranspiler.swift

class CTranspiler: CFamilyTranspiler {
    init() { super.init(target: "c") }
}
