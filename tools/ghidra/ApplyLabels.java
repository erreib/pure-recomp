// Rename default FUN_ functions using config/function_labels.csv (source file basename + address).
// Args: <config dir>
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;
import java.nio.file.*;

public class ApplyLabels extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        Path labels = Paths.get(a.length > 0 ? a[0] : "config").resolve("function_labels.csv");
        int renamed = 0, skipped = 0;
        for (String line : Files.readAllLines(labels)) {
            if (line.startsWith("function_start")) continue;
            String[] f = line.split(",", 3);
            Function fn = currentProgram.getFunctionManager().getFunctionAt(toAddr(Long.parseLong(f[0].substring(2), 16)));
            if (fn == null) { skipped++; continue; }
            if (fn.getSymbol().getSource() != SourceType.DEFAULT) { skipped++; continue; }
            String[] files = f[2].split(";");
            String base = files[0].replaceAll("\\.(cpp|h|c)$", "").replaceAll("[^A-Za-z0-9_]", "_");
            fn.setName(base + (files.length > 1 ? "_etc" : "") + "__" + fn.getEntryPoint(), SourceType.ANALYSIS);
            renamed++;
        }
        println("renamed " + renamed + ", skipped " + skipped);
    }
}
