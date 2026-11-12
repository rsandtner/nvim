package dev.rsandtner.lombokcfg;

import com.intellij.openapi.diagnostic.Logger;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.psi.PsiFile;
import de.plushnikov.intellij.plugin.lombokconfig.ConfigDiscovery;
import de.plushnikov.intellij.plugin.lombokconfig.ConfigKey;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

/**
 * Reads lombok.config straight from disk, walking up from the class's directory, instead of
 * asking LombokConfigIndex, which stays empty in the IntelliJ language server.
 */
public class DiskConfigDiscovery extends ConfigDiscovery {
  private static final Logger LOG = Logger.getInstance(DiskConfigDiscovery.class);

  /** One parsed lombok.config line for a key: op is "=", "+=", "-=" or "clear". */
  private record Entry(String op, String value) {}

  @Override
  protected Collection<String> discoverProperty(ConfigKey key, PsiFile file) {
    VirtualFile vf = file.getOriginalFile().getVirtualFile();
    if (vf == null || vf.getParent() == null) return List.of(key.getConfigDefaultValue());
    Path dir = Path.of(vf.getParent().getPath());
    String name = key.getConfigKey().toLowerCase(Locale.ROOT);

    // Directories from the class outwards, up to and including the one that stops bubbling.
    List<List<Entry>> chain = new ArrayList<>();
    for (Path d = dir; d != null; d = d.getParent()) {
      Path cfg = d.resolve("lombok.config");
      if (!Files.isRegularFile(cfg)) continue;
      Map<String, List<Entry>> parsed = parse(cfg, new HashSet<>());
      chain.add(parsed.getOrDefault(name, List.of()));
      List<Entry> stop = parsed.getOrDefault("config.stopbubbling", List.of());
      if (!stop.isEmpty() && "true".equalsIgnoreCase(stop.get(stop.size() - 1).value())) break;
    }

    Collection<String> result;
    if (isScalar(key)) {
      result = List.of(key.getConfigDefaultValue());
      outer:
      for (List<Entry> entries : chain) { // nearest file wins; its last line wins
        for (int i = entries.size() - 1; i >= 0; i--) {
          Entry e = entries.get(i);
          if (e.op().equals("=")) { result = List.of(e.value()); break outer; }
          if (e.op().equals("clear")) break outer;
        }
      }
    } else {
      LinkedHashSet<String> values = new LinkedHashSet<>();
      for (int i = chain.size() - 1; i >= 0; i--) { // outermost first, nearest last
        for (Entry e : chain.get(i)) {
          switch (e.op()) {
            case "+=" -> values.add(e.value());
            case "-=" -> values.remove(e.value());
            case "clear", "=" -> { values.clear(); if (e.op().equals("=")) values.add(e.value()); }
            default -> {}
          }
        }
      }
      result = new ArrayList<>(values);
    }
    LOG.debug("lombok.config " + name + " for " + vf.getPath() + " -> " + result);
    return result;
  }

  private static final java.lang.reflect.Method IS_SCALAR;
  static {
    try {
      IS_SCALAR = ConfigKey.class.getDeclaredMethod("isConfigScalarValue");
      IS_SCALAR.setAccessible(true);
    } catch (ReflectiveOperationException e) {
      throw new IllegalStateException(e);
    }
  }

  private static boolean isScalar(ConfigKey key) {
    try {
      return (boolean) IS_SCALAR.invoke(key);
    } catch (ReflectiveOperationException e) {
      throw new IllegalStateException(e);
    }
  }

  /** key (lower case) -> entries in file order; `import` lines are inlined where they appear. */
  private static Map<String, List<Entry>> parse(Path cfg, Set<Path> seen) {
    Map<String, List<Entry>> out = new HashMap<>();
    if (!seen.add(cfg.toAbsolutePath().normalize())) return out;
    List<String> lines;
    try {
      lines = Files.readAllLines(cfg, StandardCharsets.UTF_8);
    } catch (IOException e) {
      LOG.warn("cannot read " + cfg, e);
      return out;
    }
    for (String raw : lines) {
      String line = raw.strip();
      if (line.isEmpty() || line.startsWith("#")) continue;
      if (line.startsWith("import ")) {
        Path imported = cfg.getParent().resolve(line.substring(7).strip()).normalize();
        if (Files.isRegularFile(imported)) {
          parse(imported, seen).forEach((k, v) -> out.computeIfAbsent(k, x -> new ArrayList<>()).addAll(v));
        }
        continue;
      }
      if (line.startsWith("clear ")) {
        out.computeIfAbsent(line.substring(6).strip().toLowerCase(Locale.ROOT), x -> new ArrayList<>())
            .add(new Entry("clear", ""));
        continue;
      }
      int eq = line.indexOf('=');
      if (eq < 0) continue;
      String op = "=";
      int keyEnd = eq;
      if (eq > 0 && (line.charAt(eq - 1) == '+' || line.charAt(eq - 1) == '-')) {
        op = line.charAt(eq - 1) + "=";
        keyEnd = eq - 1;
      }
      String k = line.substring(0, keyEnd).strip().toLowerCase(Locale.ROOT);
      String v = line.substring(eq + 1).strip();
      out.computeIfAbsent(k, x -> new ArrayList<>()).add(new Entry(op, v));
    }
    return out;
  }
}
