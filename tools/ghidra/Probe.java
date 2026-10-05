// Diagnostic: what did analysis produce? Args: <hex addr of a known string> <hex addr of a known stub>
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.mem.*;

public class Probe extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        println("image base " + currentProgram.getImageBase());
        for (MemoryBlock b : currentProgram.getMemory().getBlocks())
            println("block " + b.getName() + " " + b.getStart() + "-" + b.getEnd() + " x=" + b.isExecute());
        int strings = 0, data = 0;
        DataIterator di = currentProgram.getListing().getDefinedData(true);
        while (di.hasNext()) { Data d = di.next(); data++; if (d.hasStringValue()) strings++; }
        println("defined data " + data + ", strings " + strings);
        println("functions " + currentProgram.getFunctionManager().getFunctionCount());
        for (int i = 0; i < a.length; i++) {
            Address ad = toAddr(Long.parseLong(a[i], 16));
            Data d = currentProgram.getListing().getDataAt(ad);
            Function f = currentProgram.getFunctionManager().getFunctionContaining(ad);
            Symbol[] syms = currentProgram.getSymbolTable().getSymbols(ad);
            StringBuilder sb = new StringBuilder();
            for (Symbol s : syms) sb.append(s.getName()).append(' ');
            byte[] bytes = new byte[16]; currentProgram.getMemory().getBytes(ad, bytes);
            StringBuilder hx = new StringBuilder(); for (byte x : bytes) hx.append(String.format("%02x", x));
            println(ad + ": data=" + (d == null ? "none" : d.getDataType().getName() + " '" + d.getDefaultValueRepresentation() + "'")
                + " func=" + (f == null ? "none" : f.getName()) + " syms=[" + sb + "] bytes=" + hx);
            ReferenceIterator ri = currentProgram.getReferenceManager().getReferencesTo(ad);
            int n = 0; while (ri.hasNext() && n < 5) { Reference r = ri.next(); println("   ref from " + r.getFromAddress() + " " + r.getReferenceType()); n++; }
            println("   refs total: " + currentProgram.getReferenceManager().getReferenceCountTo(ad));
        }
        // the analysis options that matter
        println("analysis options: " + currentProgram.getOptions("Analyzers").getOptionNames().size() + " entries");
        for (String n : currentProgram.getOptions("Analyzers").getOptionNames())
            if (n.toLowerCase().contains("string") || n.toLowerCase().contains("reference")) println("  " + n + " = " + currentProgram.getOptions("Analyzers").getValueAsString(n));
    }
}
