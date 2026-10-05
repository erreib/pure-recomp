// Post-script: names import stubs from config/imports.csv, labels functions by the source-file strings they
// reference, and writes config/function_map.csv, config/function_labels.csv, out/strings-xrefs.csv.
// Args: <config dir> <out dir>
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class ExportFunctions extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        Path cfg = Paths.get(a.length > 0 ? a[0] : "config"), out = Paths.get(a.length > 1 ? a[1] : "out");
        Files.createDirectories(cfg); Files.createDirectories(out);
        FunctionManager fm = currentProgram.getFunctionManager();
        Listing listing = currentProgram.getListing();

        // 1. import stubs -> names
        int named = 0;
        Path imports = cfg.resolve("imports.csv");
        if (Files.exists(imports)) {
            for (String line : Files.readAllLines(imports)) {
                if (line.startsWith("library,")) continue;
                String[] f = line.split(",");
                Address addr = toAddr(Long.parseLong(f[4].substring(2), 16));
                Function fn = fm.getFunctionAt(addr);
                if (fn == null) fn = createFunction(addr, f[2]);
                if (fn != null && !fn.getName().equals(f[2])) { fn.setName(f[2], SourceType.IMPORTED); named++; }
                else if (fn == null) { createLabel(addr, f[2], true, SourceType.IMPORTED); named++; }
            }
        }
        println("import stubs named: " + named);

        // 2. source-path strings -> functions
        Map<Function, TreeSet<String>> srcOf = new HashMap<>();
        List<String> xrefRows = new ArrayList<>();
        DataIterator di = listing.getDefinedData(true);
        while (di.hasNext() && !monitor.isCancelled()) {
            Data d = di.next();
            if (!d.hasStringValue()) continue;
            String s = StringDataInstance.getStringDataInstance(d).getStringValue();
            if (s == null) continue;
            boolean isSrc = s.contains("/Work/") || s.endsWith(".cpp") || s.endsWith(".h");
            boolean interesting = isSrc || s.startsWith("host0:") || s.contains("%");
            if (!interesting) continue;
            ReferenceIterator ri = currentProgram.getReferenceManager().getReferencesTo(d.getAddress());
            while (ri.hasNext()) {
                Reference r = ri.next();
                Function fn = fm.getFunctionContaining(r.getFromAddress());
                String fname = fn == null ? "" : fn.getName();
                xrefRows.add(d.getAddress() + "," + r.getFromAddress() + "," + fname + ",\"" + s.replace("\"", "'") + "\"");
                if (isSrc && fn != null) {
                    String base = s.replace('\\', '/');
                    base = base.substring(base.lastIndexOf('/') + 1);
                    srcOf.computeIfAbsent(fn, k -> new TreeSet<>()).add(base);
                }
            }
        }
        Files.write(out.resolve("strings-xrefs.csv"), xrefRows);
        println("string xrefs: " + xrefRows.size());

        // 3. rename default-named functions by their source file, write labels
        List<String> labels = new ArrayList<>(); labels.add("function,source_files");
        int renamed = 0;
        for (Map.Entry<Function, TreeSet<String>> e : srcOf.entrySet()) {
            Function fn = e.getKey();
            labels.add(fn.getEntryPoint() + "," + String.join(";", e.getValue()));
            if (fn.getSymbol().getSource() == SourceType.DEFAULT && e.getValue().size() == 1) {
                String b = e.getValue().first().replaceAll("[^A-Za-z0-9_]", "_");
                fn.setName(b + "__" + fn.getEntryPoint(), SourceType.ANALYSIS); renamed++;
            }
        }
        Files.write(cfg.resolve("function_labels.csv"), labels);
        println("functions labelled by source file: " + srcOf.size() + ", renamed: " + renamed);

        // 4. function map
        List<String> rows = new ArrayList<>(); rows.add("start,end,size,name");
        FunctionIterator fi = fm.getFunctions(true);
        while (fi.hasNext()) {
            Function fn = fi.next();
            Address s = fn.getEntryPoint(); Address en = fn.getBody().getMaxAddress();
            rows.add(s + "," + en + "," + fn.getBody().getNumAddresses() + "," + fn.getName());
        }
        Files.write(cfg.resolve("function_map.csv"), rows);
        println("functions: " + (rows.size() - 1) + " -> " + cfg.resolve("function_map.csv"));
    }
}
