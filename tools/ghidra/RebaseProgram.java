// Pre-script: move the image base before analysis (ghidra-allegrex applies PSP relocations on rebase).
// Arg 0: new base in hex, e.g. 08804000.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;

public class RebaseProgram extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        long base = Long.parseLong(a.length > 0 ? a[0] : "08804000", 16);
        Address cur = currentProgram.getImageBase();
        Address want = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(base);
        if (!cur.equals(want)) {
            currentProgram.setImageBase(want, true);
            println("rebased " + cur + " -> " + want);
        } else {
            println("image base already " + cur);
        }
    }
}
