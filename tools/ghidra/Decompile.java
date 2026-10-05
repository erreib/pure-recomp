// Print disassembly and decompilation of the function containing each address. Args: <out file> <hex addr>...
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import java.nio.file.*;
import java.util.*;

public class Decompile extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        StringBuilder out = new StringBuilder();
        DecompInterface di = new DecompInterface(); di.openProgram(currentProgram);
        for (int i = 1; i < a.length; i++) {
            Address ad = toAddr(Long.parseLong(a[i].replace("0x", ""), 16));
            Function fn = currentProgram.getFunctionManager().getFunctionContaining(ad);
            if (fn == null) {
                // Not analysed as a function yet (reached only through a vtable or a tail call): make one here.
                disassemble(ad);
                fn = createFunction(ad, null);
                if (fn == null) { out.append("no function at ").append(ad).append('\n'); continue; }
                out.append("(created) ");
            }
            out.append("==== ").append(fn.getName()).append(" ").append(fn.getEntryPoint()).append("-").append(fn.getBody().getMaxAddress()).append('\n');
            InstructionIterator it = currentProgram.getListing().getInstructions(fn.getBody(), true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                String refs = "";
                for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom()) {
                    Function t = currentProgram.getFunctionManager().getFunctionAt(r.getToAddress());
                    Data d = currentProgram.getListing().getDataAt(r.getToAddress());
                    if (t != null) refs += "  ; -> " + t.getName();
                    else if (d != null && d.hasStringValue()) refs += "  ; \"" + d.getDefaultValueRepresentation() + "\"";
                }
                out.append(String.format("%s  %-40s%s%n", ins.getAddress(), ins.toString(), refs));
            }
            DecompileResults res = di.decompileFunction(fn, 60, monitor);
            out.append("---- decompiled\n").append(res.getDecompiledFunction() != null ? res.getDecompiledFunction().getC() : "decompile failed: " + res.getErrorMessage()).append('\n');
        }
        di.dispose();
        Files.writeString(Paths.get(a[0]), out.toString());
        println("wrote " + a[0] + " (" + out.length() + " chars)");
    }
}
