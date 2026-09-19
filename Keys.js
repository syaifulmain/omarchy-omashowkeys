// Evdev code -> label. Codes from linux/input-event-codes.h, < 0x100 only
// (KeyMonitor.qml converts the Hyprland xkb keycode to evdev and drops
// everything outside < 0x100 at the source).

// O(1) lookup: .includes() scans, map access does not.
const MOD_SET = {
  29: true,
  97: true,
  56: true,
  100: true,
  42: true,
  54: true,
  125: true,
  126: true,
};

const MODIFIER_ORDER = [
  { codes: [29, 97], label: "Ctrl" },
  { codes: [56, 100], label: "Alt" },
  { codes: [42, 54], label: "Shift" },
  { codes: [125, 126], label: "Super" },
];

const LETTER_CODES = [
  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38,
  44, 45, 46, 47, 48, 49, 50,
];

const NAMES = {};

function fillNames() {
  const letters = "qwertyuiopasdfghjklzxcvbnm";
  for (let i = 0; i < letters.length; i++)
    NAMES[LETTER_CODES[i]] = letters.charAt(i).toUpperCase();

  const digits = {
    2: "1",
    3: "2",
    4: "3",
    5: "4",
    6: "5",
    7: "6",
    8: "7",
    9: "8",
    10: "9",
    11: "0",
  };
  for (const c in digits) NAMES[c] = digits[c];

  const punct = {
    12: "-",
    13: "=",
    26: "[",
    27: "]",
    39: ";",
    40: "'",
    41: "`",
    43: "\\",
    51: ",",
    52: ".",
    53: "/",
  };
  for (const p in punct) NAMES[p] = punct[p];

  const named = {
    1: "Esc",
    14: "Backspace",
    15: "Tab",
    28: "Enter",
    29: "Ctrl",
    42: "Shift",
    54: "Shift",
    55: "Kp*",
    56: "Alt",
    57: "Space",
    58: "CapsLock",
    69: "NumLock",
    70: "ScrollLock",
    74: "Kp-",
    78: "Kp+",
    83: "Kp.",
    87: "F11",
    88: "F12",
    96: "KpEnter",
    97: "Ctrl",
    98: "Kp/",
    99: "SysRq",
    100: "Alt",
    102: "Home",
    103: "Up",
    104: "PgUp",
    105: "Left",
    106: "Right",
    107: "End",
    108: "Down",
    109: "PgDn",
    110: "Ins",
    111: "Del",
    119: "Pause",
    121: "Mute",
    122: "VolDn",
    123: "VolUp",
    124: "Power",
    125: "Super",
    126: "Super",
    127: "Compose",
  };
  for (const n in named) NAMES[n] = named[n];

  for (let f = 1; f <= 10; f++) NAMES[58 + f] = "F" + f;

  const kpCodes = [71, 72, 73, 75, 76, 77, 79, 80, 81, 82];
  const kpDigits = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0"];
  for (let k = 0; k < kpCodes.length; k++)
    NAMES[kpCodes[k]] = "Kp" + kpDigits[k];
}

fillNames();

function label(code, overrides) {
  if (
    overrides &&
    overrides[code] !== undefined &&
    overrides[code] !== null &&
    String(overrides[code]) !== ""
  )
    return String(overrides[code]);
  return NAMES[code] || "Key" + code;
}

function isModifier(code) {
  return MOD_SET[code] === true;
}

function modifierLabels(held, overrides) {
  const out = [];
  for (const e of MODIFIER_ORDER) {
    for (const c of e.codes) {
      if (held[c]) {
        out.push(overrides && overrides[c] ? String(overrides[c]) : e.label);
        break;
      }
    }
  }
  return out;
}

// Built once, frozen ref: Panel.qml binds keyList to this.
// Without cache every binding re-eval rebuilt + sorted 120 rows.
let _allKeysCache = null;
function allKeys() {
  if (_allKeysCache) return _allKeysCache;
  const out = [];
  for (const code in NAMES)
    out.push({ code: Number(code), label: NAMES[code] });
  out.sort((a, b) => a.code - b.code);
  _allKeysCache = out;
  return out;
}
