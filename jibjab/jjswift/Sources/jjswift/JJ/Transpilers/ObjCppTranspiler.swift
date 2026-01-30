/// JibJab Objective-C++ Transpiler - Converts JJ to Objective-C++
/// Inherits all behavior from ObjCTranspiler since the transpilation is identical

public class ObjCppTranspiler: ObjCTranspiler {
    public override init(target: String = "objcpp") { super.init(target: target) }
}
