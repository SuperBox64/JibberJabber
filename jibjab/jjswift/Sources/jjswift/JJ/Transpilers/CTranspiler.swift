/// JibJab C Transpiler - Converts JJ to C
/// Inherits all behavior from CFamilyTranspiler

public class CTranspiler: CFamilyTranspiler {
    public override init(target: String = "c") { super.init(target: target) }
}
