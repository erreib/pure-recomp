#!/usr/bin/env python3
"""Checks that the control tables in docs/controls.md are the code.

  python3 tools/controls_check.py [--doc FILE] [--vendor DIR] [--quiet]

Reads the framework's sources as text (no build, no SDL):
  host/input/bindings.hpp      the Action enum, in order
  host/input/bindings.cpp      the key positions (namespace hid), the names the menu shows (kKeyNames, kMouseNames),
                               each action's settings.ini key and menu label (kInfo), its SceCtrl bit (kButtonBits),
                               and the two keyboard layouts (make_default, make_classic)
  host/shell/gamepad.hpp/.cpp  the gamepad buttons (GamepadButton, kButtonNames) and read_gamepad's held(...) lines
  host/settings/settings.hpp   the defaults of the pad tuning fields
prints the two keyboard layouts as the menu shows a binding (input::format: the names joined by " / ", "None" when
the action has none), and compares them, the gamepad buttons and the tuning defaults with the tables that follow the
markers <!-- controls_check: keyboard -->, <!-- controls_check: gamepad --> and <!-- controls_check: tuning --> in
docs/controls.md. Exit 0 when every table matches, 1 on a difference (each one printed), 2 when a source or a table
cannot be read.
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class ParseError(Exception):
    pass


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        raise ParseError(f"cannot read {path}: {e}")


def block(text, start_pattern, what, end="\n};"):
    """The text after the first match of start_pattern up to `end`."""
    m = re.search(start_pattern, text)
    if not m:
        raise ParseError(f"{what}: /{start_pattern}/ not found")
    stop = text.find(end, m.end())
    if stop < 0:
        raise ParseError(f"{what}: no end after /{start_pattern}/")
    return text[m.end():stop]


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)


def c_strings(text):
    """C string literals in order, with \\\\ and \\" unescaped."""
    return [re.sub(r"\\(.)", r"\1", s) for s in re.findall(r'"((?:[^"\\]|\\.)*)"', text)]


def enum_names(text, name, what):
    body = strip_comments(block(text, r"enum class " + name + r"\b[^{]*\{", what, end="};"))
    names = [n.strip() for n in body.split(",") if n.strip()]
    if not names or names[-1] != "Count":
        raise ParseError(f"{what}: enum {name} does not end with Count")
    return names[:-1]


# ---------------------------------------------------------------------------------------------------------------
# The code


class Code:
    def __init__(self, vendor):
        host = os.path.join(vendor, "host")
        bindings_hpp = read(os.path.join(host, "input", "bindings.hpp"))
        bindings_cpp = strip_comments(read(os.path.join(host, "input", "bindings.cpp")))
        gamepad_hpp = read(os.path.join(host, "shell", "gamepad.hpp"))
        gamepad_cpp = strip_comments(read(os.path.join(host, "shell", "gamepad.cpp")))
        settings_hpp = strip_comments(read(os.path.join(host, "settings", "settings.hpp")))

        self.actions = enum_names(bindings_hpp, "Action", "bindings.hpp")
        hid_body = block(bindings_cpp, r"namespace hid \{", "bindings.cpp hid", end="}")
        self.hid = {k: int(v) for k, v in re.findall(r"\b(\w+)\s*=\s*(\d+)", hid_body)}
        key_body = block(bindings_cpp, r"kKeyNames\[\]\s*=\s*\{", "bindings.cpp kKeyNames")
        self.key_names = {int(n): s for n, s in re.findall(r'\{\s*(\d+)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}', key_body)}
        self.key_names = {n: re.sub(r"\\(.)", r"\1", s) for n, s in self.key_names.items()}
        mouse_body = block(bindings_cpp, r"kMouseNames\[\]\s*=\s*\{", "bindings.cpp kMouseNames", end="};")
        self.mouse_names = c_strings(mouse_body)
        info_body = block(bindings_cpp, r"kInfo\[kActions\]\s*=\s*\{", "bindings.cpp kInfo")
        pairs = re.findall(r'\{\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}', info_body)
        if len(pairs) != len(self.actions):
            raise ParseError(f"bindings.cpp kInfo: {len(pairs)} entries for {len(self.actions)} actions")
        self.keys = {a: "input.bind." + k for a, (k, _) in zip(self.actions, pairs)}
        self.labels = {a: label for a, (_, label) in zip(self.actions, pairs)}
        bits_body = block(bindings_cpp, r"kButtonBits\[kActions\]\s*=\s*\{", "bindings.cpp kButtonBits", end="};")
        bits = [int(b, 0) for b in re.findall(r"\b(0x[0-9A-Fa-f]+|\d+)u?\b", bits_body)]
        if len(bits) != len(self.actions):
            raise ParseError(f"bindings.cpp kButtonBits: {len(bits)} entries for {len(self.actions)} actions")
        self.bits = dict(zip(self.actions, bits))
        self.layouts = {"default": self.layout(bindings_cpp, "make_default"),
                        "classic": self.layout(bindings_cpp, "make_classic")}

        self.pad_buttons = enum_names(gamepad_hpp, "GamepadButton", "gamepad.hpp")
        names_body = block(gamepad_cpp, r"kButtonNames\s*=\s*\{", "gamepad.cpp kButtonNames", end="};")
        sdl_names = c_strings(names_body)
        if len(sdl_names) != len(self.pad_buttons):
            raise ParseError(f"gamepad.cpp kButtonNames: {len(sdl_names)} names for {len(self.pad_buttons)} buttons")
        self.sdl_name = dict(zip(self.pad_buttons, sdl_names))
        read_body = block(gamepad_cpp, r"void read_gamepad\(", "gamepad.cpp read_gamepad", end="\n}")
        # pad name -> (bit with input.confirm=east, bit with input.confirm=south)
        self.pad_map = {}
        for button, bit in re.findall(r"held\(GamepadButton::(\w+),\s*0x([0-9A-Fa-f]+)u?\)", read_body):
            self.pad_map[self.sdl_name[button]] = (int(bit, 16), int(bit, 16))
        for button, south, east in re.findall(
                r"held\(GamepadButton::(\w+),\s*tuning\.confirm_south\s*\?\s*0x([0-9A-Fa-f]+)u?\s*:\s*0x([0-9A-Fa-f]+)u?\)",
                read_body):
            self.pad_map[self.sdl_name[button]] = (int(east, 16), int(south, 16))
        if not self.pad_map:
            raise ParseError("gamepad.cpp read_gamepad: no held(...) lines")

        self.tuning = {}
        for key, member in (("input.dead_zone", "dead_zone"), ("input.trigger", "trigger"),
                            ("input.right_stick_zone", "right_stick_zone")):
            m = re.search(r"\bfloat " + member + r"\{([0-9.]+)f\}", settings_hpp)
            if not m:
                raise ParseError(f"settings.hpp: float {member} default not found")
            self.tuning[key] = f"{float(m[1]):.2f}"
        m = re.search(r"\bbool confirm_south\{(\w*)\}", settings_hpp)
        if not m:
            raise ParseError("settings.hpp: confirm_south default not found")
        self.tuning["input.confirm"] = "south" if m[1] == "true" else "east"
        m = re.search(r"\bRightStick right_stick\{RightStick::(\w+)\}", settings_hpp)
        if not m:
            raise ParseError("settings.hpp: right_stick default not found")
        self.tuning["input.right_stick"] = {"Camera": "camera", "DPad": "dpad", "Off": "off"}[m[1]]
        m = re.search(r"\bbool mouse\{(\w*)\}", settings_hpp)
        if not m:
            raise ParseError("settings.hpp: mouse default not found")
        self.tuning["input.mouse"] = "1" if m[1] == "true" else "0"

    def binding_name(self, arg, where):
        m = re.fullmatch(r"key\(hid::(\w+)\)", arg)
        if m:
            if m[1] not in self.hid:
                raise ParseError(f"{where}: hid::{m[1]} is not in namespace hid")
            position = self.hid[m[1]]
            return self.key_names.get(position, f"Key {position}")
        m = re.fullmatch(r"mouse_button\((\d+)\)", arg)
        if m:
            return self.mouse_names[int(m[1]) - 1]
        raise ParseError(f"{where}: binding {arg!r} not understood")

    def layout(self, text, function):
        body = block(text, r"Bindings " + function + r"\(\)\s*\{", "bindings.cpp " + function, end="\n}")
        slots = {a: [] for a in self.actions}
        for action, args in re.findall(r"\bset\(Action::(\w+),\s*([^;]*)\);", body):
            if action not in slots:
                raise ParseError(f"bindings.cpp {function}: Action::{action} is not in the enum")
            parts = [p.strip() for p in re.split(r",\s*(?=key\(|mouse_button\()", args.strip())]
            slots[action] = [self.binding_name(p, f"bindings.cpp {function}") for p in parts if p != "kNone"]
        return {a: " / ".join(s) if s else "None" for a, s in slots.items()}

    def stick_effect(self, action):
        """What read() and SdlPad::sample make of a stick or camera action, as PURE_TRACE_PAD prints it."""
        m = re.fullmatch(r"(Stick|Camera)(Up|Left|Down|Right)", action)
        if not m:
            return None
        stick = "analog" if m[1] == "Stick" else "right"
        axis = "Y" if m[2] in ("Up", "Down") else "X"
        value = 1 if m[2] in ("Up", "Left") else 255
        return f"{stick} {axis} {value}"


# ---------------------------------------------------------------------------------------------------------------
# The document


def norm(cell):
    return " ".join(cell.replace("`", "").split())


def doc_table(text, marker):
    """The rows of the first table after <!-- controls_check: marker -->, as dicts by header."""
    tag = f"<!-- controls_check: {marker} -->"
    at = text.find(tag)
    if at < 0:
        raise ParseError(f"docs/controls.md: marker {tag} not found")
    lines = text[at + len(tag):].split("\n")
    rows, header = [], None
    for line in lines:
        s = line.strip()
        if not s.startswith("|"):
            if header is None and not s:
                continue
            if header is None:
                raise ParseError(f"docs/controls.md: no table right after {tag}")
            break
        cells = [norm(c) for c in s.strip("|").split("|")]
        if header is None:
            header = cells
        elif all(re.fullmatch(r":?-+:?", c) for c in cells):
            continue
        else:
            rows.append(dict(zip(header, cells)))
    if not rows:
        raise ParseError(f"docs/controls.md: the table after {tag} is empty")
    return header, rows


def column(header, prefix, marker):
    for h in header:
        if h.lower().startswith(prefix.lower()):
            return h
    raise ParseError(f"docs/controls.md {marker} table: no column starting {prefix!r} (columns: {header})")


def check_keyboard(code, text, problems):
    header, rows = doc_table(text, "keyboard")
    key_col = column(header, "settings.ini key", "keyboard")
    label_col = column(header, "Menu label", "keyboard")
    effect_col = column(header, "PSP effect", "keyboard")
    default_col = column(header, "Default layout", "keyboard")
    classic_col = column(header, "Classic layout", "keyboard")
    by_key = {}
    for row in rows:
        by_key.setdefault(row.get(key_col, ""), row)
    for action in code.actions:
        key = code.keys[action]
        row = by_key.pop(key, None)
        if row is None:
            problems.append(f"keyboard: no row for {key} ({action})")
            continue
        expected = {label_col: norm(code.labels[action]), default_col: code.layouts["default"][action],
                    classic_col: code.layouts["classic"][action]}
        effect = code.stick_effect(action)
        for col, want in expected.items():
            if row.get(col, "") != want:
                problems.append(f"keyboard: {key} {col!r}: the doc has {row.get(col, '')!r}, the code {want!r}")
        got = row.get(effect_col, "")
        if effect is not None:
            if got != effect:
                problems.append(f"keyboard: {key} {effect_col!r}: the doc has {got!r}, the code {effect!r}")
        else:
            m = re.search(r"0x([0-9A-Fa-f]+)", got)
            if not m or int(m[1], 16) != code.bits[action]:
                problems.append(f"keyboard: {key} {effect_col!r}: the doc has {got!r}, the code bit 0x{code.bits[action]:04X}")
    for key in by_key:
        problems.append(f"keyboard: the doc has a row for {key!r}, which is no action in the code")


def check_gamepad(code, text, problems):
    header, rows = doc_table(text, "gamepad")
    name_col = column(header, "SDL button", "gamepad")
    east_col = column(header, "PSP, input.confirm=east", "gamepad")
    south_col = column(header, "PSP, input.confirm=south", "gamepad")
    bit_names = {code.bits[a]: a for a in code.actions if code.bits[a]}
    seen = set()
    for row in rows:
        name = row.get(name_col, "")
        seen.add(name)
        if name not in code.pad_map:
            problems.append(f"gamepad: the doc maps {name!r}, which read_gamepad does not")
            continue
        for col, want in ((east_col, code.pad_map[name][0]), (south_col, code.pad_map[name][1])):
            got = row.get(col, "")
            m = re.fullmatch(r"(.*?)\s*0x([0-9A-Fa-f]+)", got)
            if not m or int(m[2], 16) != want:
                problems.append(f"gamepad: {name} {col!r}: the doc has {got!r}, the code 0x{want:04X}")
            elif not m[1].lower().endswith(bit_names.get(want, "?").lower()):
                problems.append(f"gamepad: {name} {col!r}: {m[1]!r} is not the name of 0x{want:04X} "
                                f"({bit_names.get(want, '?')})")
    for name in sorted(set(code.pad_map) - seen):
        problems.append(f"gamepad: read_gamepad maps {name!r} (0x{code.pad_map[name][0]:04X}), the doc has no row")


def check_tuning(code, text, problems):
    header, rows = doc_table(text, "tuning")
    key_col = column(header, "settings.ini key", "tuning")
    default_col = column(header, "Default", "tuning")
    by_key = {row.get(key_col, ""): row for row in rows}
    for key, want in code.tuning.items():
        row = by_key.get(key)
        if row is None:
            problems.append(f"tuning: no row for {key}")
            continue
        got = row.get(default_col, "")
        same = got == want
        if not same:
            try:
                same = abs(float(got) - float(want)) < 1e-6
            except ValueError:
                pass
        if not same:
            problems.append(f"tuning: {key} default: the doc has {got!r}, the code {want!r}")


def main(argv=None):
    p = argparse.ArgumentParser(prog="controls_check.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--doc", default=os.path.join(ROOT, "docs", "controls.md"))
    p.add_argument("--vendor", default=os.path.join(ROOT, "vendor", "portablekit"))
    p.add_argument("--quiet", action="store_true", help="print only the differences and the verdict")
    opts = p.parse_args(argv)
    try:
        code = Code(opts.vendor)
        text = read(opts.doc)
        if not opts.quiet:
            width = max(len(code.keys[a]) for a in code.actions)
            print(f"{'settings.ini key':<{width}}  {'default layout':<18}  classic layout")
            for a in code.actions:
                print(f"{code.keys[a]:<{width}}  {code.layouts['default'][a]:<18}  {code.layouts['classic'][a]}")
            print("gamepad (input.confirm=east / south): " + ", ".join(
                f"{n} 0x{e:04X}" + (f"/0x{s:04X}" if s != e else "") for n, (e, s) in code.pad_map.items()))
            print("tuning defaults: " + ", ".join(f"{k}={v}" for k, v in code.tuning.items()))
        problems = []
        check_keyboard(code, text, problems)
        check_gamepad(code, text, problems)
        check_tuning(code, text, problems)
    except ParseError as e:
        print(f"controls_check: {e}")
        return 2
    doc = os.path.abspath(opts.doc)
    shown = os.path.relpath(doc, ROOT) if doc.startswith(ROOT + os.sep) else opts.doc
    for line in problems:
        print("DIFF " + line)
    if problems:
        print(f"controls_check: FAIL, {len(problems)} difference(s) between {shown} and the code")
        return 1
    print(f"controls_check: OK, {shown} matches the code "
          f"({len(code.actions)} actions in two layouts, {len(code.pad_map)} gamepad buttons, "
          f"{len(code.tuning)} tuning defaults)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
