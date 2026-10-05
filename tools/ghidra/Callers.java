// Print the functions that reference each given address (calls, jumps, data refs). Args: <out file> <hex addr>...
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.*;
import java.nio.file.*;

public class Callers extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        StringBuilder out = new StringBuilder();
        for (int i = 1; i < a.length; i++) {
            Address ad = toAddr(Long.parseLong(a[i].replace("0x", ""), 16));
            Function target = currentProgram.getFunctionManager().getFunctionContaining(ad);
            out.append("==== refs to ").append(ad).append(target != null ? " (" + target.getName() + ")" : "").append('\n');
            ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(ad);
            int n = 0;
            while (it.hasNext()) {
                Reference r = it.next();
                Function f = currentProgram.getFunctionManager().getFunctionContaining(r.getFromAddress());
                out.append(String.format("  %s  %-10s from %s%n", r.getFromAddress(), r.getReferenceType(), f != null ? f.getName() : "?"));
                if (++n > 60) { out.append("  ...\n"); break; }
            }
        }
        Files.writeString(Paths.get(a[0]), out.toString());
        println("wrote " + a[0]);
    }
}
