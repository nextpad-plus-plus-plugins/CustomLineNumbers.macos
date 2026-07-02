// CustomLineNumbers — macOS port
// Original Windows plugin: "CustomLineNumbers" by Andreas Heim (GPL v3, 2018–2024).
// https://github.com/AndreasHeimDE/CustomLineNumbers  (Delphi / Object Pascal)
//
// Feature: display Notepad++'s line numbers in a custom format — HEXADECIMAL or
// RELATIVE (Vim-style: distance from the caret line) — instead of plain decimal,
// in the editor's line-number margin, with a configurable starting line number
// (offset). The original also tints the status-bar line/column readout.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-LIMITATION INVESTIGATION (decides the whole architecture — read this)
// ─────────────────────────────────────────────────────────────────────────────
// On Windows the plugin owns the line-number margin: in Activate() it flips
// margin 0 to SC_MARGIN_RTEXT and writes each visible line's string with
// SCI_MARGINSETTEXT / SCI_MARGINSETSTYLE (Main.pas: Activate + UpdateLineNumbers).
//
// On the macOS fork the HOST owns margin 0:
//   • It sets margin-0 TYPE = SC_MARGIN_NUMBER once at editor init
//     (notepad-plus-plus-macos/src/EditorView.mm:1870, applyDefaultTheme).
//   • It AGGRESSIVELY re-asserts margin-0 WIDTH from the line count via
//     recomputeLineNumberMargin / maintainLineNumberWidthOnEdit on SCN_MODIFIED
//     (linesAdded≠0), SCN_ZOOM, and every prefs/theme/font/language change
//     (EditorView.mm:2529-2561, 2617, 2697-2706, 5201, 5318).
// So repurposing margin 0 (approach (a)) is NOT viable: even though the host
// never flips the TYPE back, it would clobber the margin-0 WIDTH out from under
// us on essentially every line-count-changing edit and every zoom, and it would
// also replace the decimal line numbers the user still expects.
//
// HOWEVER: the host never calls SCI_SETMARGINS — the Scintilla margin count
// stays at the default (indices 0-4, all occupied: 0=line#, 1=bookmarks,
// 2=change-history, 3=fold, 4=git). The host never iterates margins generically
// and applyDefaultTheme only ever names indices 0-4 explicitly. So we raise the
// margin count to 6 ourselves and own a brand-new SC_MARGIN_RTEXT margin at
// INDEX 5. The host leaves it completely untouched.  →  APPROACH (b).
//
// Consequence (documented honestly): our hex/relative numbers appear in an
// EXTRA margin to the right of the host's decimal margin 0; we SUPPLEMENT, not
// replace, the host's line numbers. The host's decimal margin can be turned off
// by the user (Prefs ▸ show line numbers) to leave only ours visible.  And
// The host owns and continuously rewrites the status-bar line/column readout, so a
// plugin cannot reformat it (NPPM_SETSTATUSBAR, where a host implements it, targets
// a dedicated plugin status field — not the line/column readout). So the status-bar
// part of the Windows plugin is dropped. Both limitations are host-capability
// gaps; no host change is made or needed. One-line restore if the host ever
// exposes margin-0 formatting: point kCLNMargin at 0 and stop calling
// SCI_SETMARGINS (see kCLNMargin below).
//
// Platform mapping: ::SendMessage → nppData._sendMessage; Win32 settings DIALOG
// → programmatic AppKit modal NSWindow; INI config under NPPM_GETPLUGINSCONFIGDIR
// (same file layout as the Windows TIniFile, "<PluginName>.ini").

#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"
#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstring>
#include <map>
#include <string>

// ── constants ────────────────────────────────────────────────────────────────
static const char *PLUGIN_NAME = "CustomLineNumbers";
static const int   nbFunc      = 8;   // 6 commands + 2 separators (empty-name slots)

// Our own, plugin-owned margin (host occupies 0-4 and never raises the count).
// RESTORE NOTE: if a future host exposes margin-0 formatting, set this to 0 and
// remove the SCI_SETMARGINS call in ensureMargin().
static const int  kCLNMargin     = 5;
// Style slot for our margin text. The Windows plugin uses STYLE_MAX for its
// custom margin style; we mirror that (255 is well clear of host styling).
static const int  kCLNMarginStyle = STYLE_MAX;        // 255
static const int  kCLNMarginWidthMin = 36;            // px floor like host's 30

// Display modes (mirror the Windows feature set: hex / relative / off).
enum CLNMode { kModeOff = 0, kModeHex = 1, kModeRelative = 2, kModeDecimal = 3 };

// Menu item indices.
enum {
    IDX_OFF = 0, IDX_HEX = 1, IDX_REL = 2, IDX_DEC = 3, IDX_SEP1 = 4, IDX_SETTINGS = 5,
    IDX_SEP2 = 6, IDX_ABOUT = 7
    // IDX_SEP1 / IDX_SEP2 are left empty-name by memset → rendered as separators.
};

// ── plugin-wide state ────────────────────────────────────────────────────────
NppData  nppData;              // global so helpers can reach the host
FuncItem funcItem[nbFunc];

struct CLNSettings {
    CLNMode mode         = kModeOff;   // matches Windows default: enabled but…
    int     lineOffset   = 0;          // "Line numbers start at" (Windows: 0)
    int     colOffset    = 0;          // kept for parity (status bar only; no-op on mac)
    // Custom margin font styling (relative/current-line emphasis), parity w/ Win.
    bool    useFgColor   = false;
    long    fgColor      = 0x808080;   // 0x00BBGGRR (Scintilla colour order)
    bool    useBgColor   = false;
    long    bgColor      = 0xE4E4E4;
    bool    bold         = false;
};
static CLNSettings g_set;

// ── platform helpers ─────────────────────────────────────────────────────────
static intptr_t sci(NppHandle h, uint32_t msg, uintptr_t w = 0, intptr_t l = 0) {
    return h ? nppData._sendMessage(h, msg, w, l) : 0;
}

static NppHandle currentScintilla() {
    int which = -1;
    nppData._sendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return (which == 0) ? nppData._scintillaMainHandle
         : (which == 1) ? nppData._scintillaSecondHandle : 0;
}

// Both editor views (main + second). Either handle may be 0 if a view is absent;
// sci() guards against that. We always configure/refresh both so split-view and
// the inactive view stay correct (the Windows plugin iterates MAIN_VIEW..SUB_VIEW).
static NppHandle viewHandle(int idx) {
    return (idx == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
}

// ── settings persistence (INI under NPPM_GETPLUGINSCONFIGDIR) ─────────────────
// Same file shape/location as the Windows TIniFile: <configdir>/CustomLineNumbers.ini
static NSString *configPath() {
    @autoreleasepool {
        char buf[2048] = {0};
        nppData._sendMessage(nppData._nppHandle, NPPM_GETPLUGINSCONFIGDIR,
                             (uintptr_t)sizeof(buf), (intptr_t)buf);
        NSString *dir = (buf[0] != '\0')
            ? [NSString stringWithUTF8String:buf]
            : [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                  NSUserDomainMask, YES).firstObject
                  stringByAppendingPathComponent:@"Nextpad++/plugins/Config"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        return [dir stringByAppendingPathComponent:@"CustomLineNumbers.ini"];
    }
}

static std::string trim(const std::string &s) {
    size_t b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    size_t e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

static void loadSettings() {
    @autoreleasepool {
        NSString *content = [NSString stringWithContentsOfFile:configPath()
                                                      encoding:NSUTF8StringEncoding error:nil];
        if (!content) return;  // first run → keep defaults
        std::map<std::string, std::string> kv;
        for (NSString *raw in [content componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet newlineCharacterSet]]) {
            std::string line = trim(raw.UTF8String);
            if (line.empty() || line[0] == ';' || line[0] == '#' || line[0] == '[') continue;
            size_t eq = line.find('=');
            if (eq == std::string::npos) continue;
            kv[trim(line.substr(0, eq))] = trim(line.substr(eq + 1));
        }
        auto getInt = [&](const char *k, long def) -> long {
            auto it = kv.find(k);
            if (it == kv.end()) return def;
            // accept decimal or 0x.. / $.. hex (Windows wrote $%.8x for colours)
            std::string v = it->second;
            if (!v.empty() && v[0] == '$') return strtol(v.c_str() + 1, nullptr, 16);
            return strtol(v.c_str(), nullptr, 0);
        };
        auto getBool = [&](const char *k, bool def) -> bool {
            auto it = kv.find(k);
            if (it == kv.end()) return def;
            std::string v = it->second;
            return v == "1" || v == "true" || v == "TRUE" || v == "True";
        };
        // Mode: prefer explicit "mode", else fall back to the Windows
        // relativeNumbers/hexNumbers/enabled trio for settings-file compatibility.
        if (kv.count("mode")) {
            long m = getInt("mode", kModeOff);
            g_set.mode = (m == kModeHex || m == kModeRelative || m == kModeDecimal) ? (CLNMode)m : kModeOff;
        } else {
            bool enabled = getBool("enabled", false);
            bool rel     = getBool("relativeNumbers", false);
            bool hex     = getBool("hexNumbers", false);
            // Windows "enabled + not hex + not relative" == custom decimal.
            g_set.mode = !enabled ? kModeOff : rel ? kModeRelative : hex ? kModeHex : kModeDecimal;
        }
        g_set.lineOffset = (int)getInt("lineOffset", 0);
        g_set.colOffset  = (int)getInt("columnOffset", g_set.lineOffset);
        g_set.useFgColor = getBool("useCurLineFontFgColor", false);
        g_set.fgColor    = getInt("curLineFontFgColor", 0x808080);
        g_set.useBgColor = getBool("useCurLineFontBgColor", false);
        g_set.bgColor    = getInt("curLineFontBgColor", 0xE4E4E4);
        g_set.bold       = getBool("curLineBold", false);
    }
}

static void saveSettings() {
    @autoreleasepool {
        char b[2048];
        std::string s = "[Header]\nVersion=1.1\n[Settings]\n";
        snprintf(b, sizeof(b), "mode=%d\n", (int)g_set.mode);                 s += b;
        snprintf(b, sizeof(b), "enabled=%s\n", g_set.mode != kModeOff ? "1":"0"); s += b;
        snprintf(b, sizeof(b), "hexNumbers=%s\n", g_set.mode == kModeHex ? "1":"0"); s += b;
        snprintf(b, sizeof(b), "relativeNumbers=%s\n", g_set.mode == kModeRelative ? "1":"0"); s += b;
        snprintf(b, sizeof(b), "lineOffset=%d\n", g_set.lineOffset);          s += b;
        snprintf(b, sizeof(b), "columnOffset=%d\n", g_set.colOffset);         s += b;
        snprintf(b, sizeof(b), "useCurLineFontFgColor=%s\n", g_set.useFgColor ? "1":"0"); s += b;
        snprintf(b, sizeof(b), "curLineFontFgColor=$%.8lx\n", (unsigned long)(g_set.fgColor & 0xFFFFFF)); s += b;
        snprintf(b, sizeof(b), "useCurLineFontBgColor=%s\n", g_set.useBgColor ? "1":"0"); s += b;
        snprintf(b, sizeof(b), "curLineFontBgColor=$%.8lx\n", (unsigned long)(g_set.bgColor & 0xFFFFFF)); s += b;
        snprintf(b, sizeof(b), "curLineBold=%s\n", g_set.bold ? "1":"0");     s += b;
        [[NSString stringWithUTF8String:s.c_str()] writeToFile:configPath()
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ── margin management (approach (b): our own margin index 5) ──────────────────

// Configure the style used for our margin text on one view, copying the host's
// line-number font so our digits visually match, then applying plugin colours.
static void configMarginStyle(NppHandle h) {
    if (!h) return;
    // Copy font name from STYLE_LINENUMBER so our text matches the host's look.
    char font[256] = {0};
    sci(h, SCI_STYLEGETFONT, STYLE_LINENUMBER, (intptr_t)font);
    if (font[0]) sci(h, SCI_STYLESETFONT, kCLNMarginStyle, (intptr_t)font);
    long size = sci(h, SCI_STYLEGETSIZE, STYLE_LINENUMBER);
    if (size > 0) sci(h, SCI_STYLESETSIZE, kCLNMarginStyle, size);

    long fg = g_set.useFgColor ? g_set.fgColor : sci(h, SCI_STYLEGETFORE, STYLE_LINENUMBER);
    long bg = g_set.useBgColor ? g_set.bgColor : sci(h, SCI_STYLEGETBACK, STYLE_LINENUMBER);
    sci(h, SCI_STYLESETFORE, kCLNMarginStyle, fg);
    sci(h, SCI_STYLESETBACK, kCLNMarginStyle, bg);
    sci(h, SCI_STYLESETBOLD, kCLNMarginStyle, g_set.bold ? 1 : 0);
}

// Make sure our margin exists with the right type/style on one view. Idempotent.
static void ensureMargin(NppHandle h) {
    if (!h) return;
    // Raise the margin count so index 5 is addressable (host never does this).
    if (sci(h, SCI_GETMARGINS) <= kCLNMargin)
        sci(h, SCI_SETMARGINS, (uintptr_t)(kCLNMargin + 1));
    sci(h, SCI_SETMARGINTYPEN, (uintptr_t)kCLNMargin, SC_MARGIN_RTEXT);
    sci(h, SCI_SETMARGINSENSITIVEN, (uintptr_t)kCLNMargin, 0);
    configMarginStyle(h);
}

static void clearMargin(NppHandle h) {
    if (!h) return;
    sci(h, SCI_MARGINTEXTCLEARALL);
    sci(h, SCI_SETMARGINWIDTHN, (uintptr_t)kCLNMargin, 0);
}

// Format one line's number string into buf.
static void formatNumber(char *buf, size_t n, long lineIdx, long caretLine) {
    if (g_set.mode == kModeRelative) {
        if (lineIdx == caretLine)
            snprintf(buf, n, "%ld", lineIdx + g_set.lineOffset);   // current line: absolute
        else
            snprintf(buf, n, "%ld", labs(lineIdx - caretLine));    // others: distance
    } else if (g_set.mode == kModeHex) {
        snprintf(buf, n, "%lx", (unsigned long)(lineIdx + g_set.lineOffset));
    } else {   // kModeDecimal: base-10 line numbers with the custom start offset
        snprintf(buf, n, "%ld", lineIdx + g_set.lineOffset);
    }
}

// Compute and set our margin width to fit the widest string we'll show, using
// the host's STYLE_LINENUMBER metric on the line count (parity with the host's
// own recomputeLineNumberMargin).
static void fitMarginWidth(NppHandle h, long lineCount, long caretLine) {
    long top = lineCount > 0 ? lineCount - 1 : 0;
    long w;
    if (g_set.mode == kModeRelative) {
        // Caret-INDEPENDENT worst case so the width never jitters as the caret
        // moves: the widest relative distance is `top`, and the current line always
        // shows its absolute number (widest at either document end, with the offset
        // applied — so a large lineOffset is never clipped). Measure each candidate
        // and keep the widest.
        long cand[3] = { top, top + g_set.lineOffset, (long)g_set.lineOffset };
        w = kCLNMarginWidthMin;
        char s[80];
        for (long v : cand) {
            snprintf(s, sizeof(s), "_%ld", v);            // pad like the host ("_")
            long m = sci(h, SCI_TEXTWIDTH, kCLNMarginStyle, (intptr_t)s);
            if (m > w) w = m;
        }
    } else {
        // hex / off: widest is the top line number (offset-aware, caret-independent).
        char widest[64];
        formatNumber(widest, sizeof(widest), top, caretLine);
        std::string measure = std::string("_") + widest; // pad like the host ("_")
        w = sci(h, SCI_TEXTWIDTH, kCLNMarginStyle, (intptr_t)measure.c_str());
        if (w < kCLNMarginWidthMin) w = kCLNMarginWidthMin;
    }
    sci(h, SCI_SETMARGINWIDTHN, (uintptr_t)kCLNMargin, w);
}

// Repaint our margin's per-line text for the currently visible range of one view.
// Mirrors UpdateLineNumbers in Main.pas: only the visible window is (re)written,
// which keeps it fast on large files; relative mode re-renders on caret moves.
static void updateView(NppHandle h) {
    if (!h || g_set.mode == kModeOff) return;

    long lineCount = (long)sci(h, SCI_GETLINECOUNT);
    if (lineCount <= 0) return;
    long caretLine = (long)sci(h, SCI_LINEFROMPOSITION, (uintptr_t)sci(h, SCI_GETCURRENTPOS));

    fitMarginWidth(h, lineCount, caretLine);

    long first = (long)sci(h, SCI_GETFIRSTVISIBLELINE);
    long onScreen = (long)sci(h, SCI_LINESONSCREEN);
    if (first < 0) first = 0;
    // first visible is a *visual* line; map to a document line, then walk doc lines.
    long docFirst = (long)sci(h, SCI_DOCLINEFROMVISIBLE, (uintptr_t)first);
    long start = docFirst;
    long stop  = docFirst + onScreen + 1;                 // +1 for the partial bottom line
    if (stop > lineCount - 1) stop = lineCount - 1;
    if (start < 0) start = 0;

    char num[64];
    for (long i = start; i <= stop; ++i) {
        formatNumber(num, sizeof(num), i, caretLine);
        sci(h, SCI_MARGINSETSTYLE, (uintptr_t)i, kCLNMarginStyle);
        sci(h, SCI_MARGINSETTEXT,  (uintptr_t)i, (intptr_t)num);
    }
}

static void updateAllViews() {
    updateView(nppData._scintillaMainHandle);
    updateView(nppData._scintillaSecondHandle);
}

// Apply the current mode to both views (set up or tear down the margin).
static void applyMode() {
    for (int v = 0; v < 2; ++v) {
        NppHandle h = viewHandle(v);
        if (!h) continue;
        if (g_set.mode == kModeOff) {
            clearMargin(h);
        } else {
            ensureMargin(h);
        }
    }
    updateAllViews();
}

// Reflect the current mode in the menu check marks.
static void syncMenuChecks() {
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                         (uintptr_t)funcItem[IDX_OFF]._cmdID, g_set.mode == kModeOff);
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                         (uintptr_t)funcItem[IDX_HEX]._cmdID, g_set.mode == kModeHex);
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                         (uintptr_t)funcItem[IDX_REL]._cmdID, g_set.mode == kModeRelative);
    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                         (uintptr_t)funcItem[IDX_DEC]._cmdID, g_set.mode == kModeDecimal);
}

static void setMode(CLNMode m) {
    g_set.mode = m;
    saveSettings();
    syncMenuChecks();
    applyMode();
}

// ── menu commands ─────────────────────────────────────────────────────────────
static void cmdOff()      { setMode(kModeOff); }
static void cmdHex()      { setMode(kModeHex); }
static void cmdRelative() { setMode(kModeRelative); }
static void cmdDecimal()  { setMode(kModeDecimal); }

// ── About ─────────────────────────────────────────────────────────────────────
static void showAbout() {
    @autoreleasepool {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"CustomLineNumbers";
        a.informativeText =
            @"Display line numbers in a custom format — hexadecimal, relative "
            @"(Vim-style distance from the caret line), or decimal with a custom "
            @"start — in an extra editor margin, with a configurable starting number.\n\n"
            @"Original Notepad++ plugin by Andreas Heim (GPL v3). macOS port by "
            @"Andrey Letov.";
        [a addButtonWithTitle:@"OK"];
        [a runModal];
    }
}

// ── settings dialog (programmatic AppKit modal — replaces the Win32 DIALOG) ────
// Mirrors dialog_TfrmSettings: line/column start offsets, mode (hex/relative/
// off), and optional fg/bg colour + bold for the margin text.
@interface CLNSettingsController : NSObject <NSWindowDelegate>
@end

@implementation CLNSettingsController {
    NSWindow      *_window;
    NSPopUpButton *_modePopup;
    NSTextField   *_lineOffset;
    NSTextField   *_colOffset;
    NSButton      *_useFg, *_useBg, *_bold;
    NSColorWell   *_fgWell, *_bgWell;
}

static NSColor *colorFromScintilla(long c) {
    CGFloat r = (c & 0xFF) / 255.0, g = ((c >> 8) & 0xFF) / 255.0, b = ((c >> 16) & 0xFF) / 255.0;
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}
static long scintillaFromColor(NSColor *c) {
    NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    long r = (long)lround(rgb.redComponent   * 255.0);
    long g = (long)lround(rgb.greenComponent * 255.0);
    long b = (long)lround(rgb.blueComponent  * 255.0);
    return (b << 16) | (g << 8) | r;   // Scintilla 0x00BBGGRR
}

- (NSTextField *)label:(NSString *)s at:(NSRect)f to:(NSView *)v {
    NSTextField *t = [NSTextField labelWithString:s];
    t.frame = f; [v addSubview:t]; return t;
}

- (void)build {
    const CGFloat W = 420, H = 320;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"CustomLineNumbers — Settings";
    _window.delegate = self;
    _window.releasedWhenClosed = NO;
    NSView *root = _window.contentView;

    CGFloat y = H - 48;
    [self label:@"Number format:" at:NSMakeRect(20, y, 120, 22) to:root];
    _modePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, y - 2, 220, 26)];
    [_modePopup addItemsWithTitles:@[@"Off (decimal — host default)", @"Hexadecimal", @"Relative (Vim-style)", @"Decimal (custom start)"]];
    [_modePopup selectItemAtIndex:(NSInteger)g_set.mode];
    [root addSubview:_modePopup];

    y -= 44;
    [self label:@"Line numbers start at:" at:NSMakeRect(20, y, 180, 22) to:root];
    _lineOffset = [[NSTextField alloc] initWithFrame:NSMakeRect(210, y - 2, 80, 24)];
    _lineOffset.stringValue = [NSString stringWithFormat:@"%d", g_set.lineOffset];
    [root addSubview:_lineOffset];

    y -= 34;
    [self label:@"Column numbers start at:" at:NSMakeRect(20, y, 180, 22) to:root];
    _colOffset = [[NSTextField alloc] initWithFrame:NSMakeRect(210, y - 2, 80, 24)];
    _colOffset.stringValue = [NSString stringWithFormat:@"%d", g_set.colOffset];
    _colOffset.enabled = NO;            // status-bar only on Windows; no-op on macOS
    [root addSubview:_colOffset];
    NSTextField *note = [self label:@"(column offset affects the status bar only — not reachable on macOS)"
                                 at:NSMakeRect(20, y - 22, W - 40, 18) to:root];
    note.font = [NSFont systemFontOfSize:10];
    note.textColor = [NSColor secondaryLabelColor];

    y -= 60;
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(20, y - 70, W - 40, 96)];
    box.title = @"Margin text appearance";
    [root addSubview:box];
    {
        _useFg = [NSButton checkboxWithTitle:@"Custom color" target:nil action:nil];
        _useFg.frame = NSMakeRect(14, 50, 130, 20);
        _useFg.state = g_set.useFgColor ? NSControlStateValueOn : NSControlStateValueOff;
        [box addSubview:_useFg];
        _fgWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(150, 48, 44, 24)];
        _fgWell.color = colorFromScintilla(g_set.fgColor);
        [box addSubview:_fgWell];

        _useBg = [NSButton checkboxWithTitle:@"Custom background" target:nil action:nil];
        _useBg.frame = NSMakeRect(210, 50, 150, 20);
        _useBg.state = g_set.useBgColor ? NSControlStateValueOn : NSControlStateValueOff;
        [box addSubview:_useBg];
        _bgWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(346, 48, 24, 24)];
        _bgWell.color = colorFromScintilla(g_set.bgColor);
        [box addSubview:_bgWell];

        _bold = [NSButton checkboxWithTitle:@"Bold" target:nil action:nil];
        _bold.frame = NSMakeRect(14, 16, 130, 20);
        _bold.state = g_set.bold ? NSControlStateValueOn : NSControlStateValueOff;
        [box addSubview:_bold];
    }

    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(ok:)];
    ok.frame = NSMakeRect(W - 200, 14, 84, 30); ok.keyEquivalent = @"\r";
    [root addSubview:ok];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.frame = NSMakeRect(W - 104, 14, 84, 30); cancel.keyEquivalent = @"\e";
    [root addSubview:cancel];
}

- (void)apply {
    [_window makeFirstResponder:nil];   // commit field edits
    g_set.mode       = (CLNMode)_modePopup.indexOfSelectedItem;
    g_set.lineOffset = _lineOffset.intValue;
    g_set.useFgColor = (_useFg.state == NSControlStateValueOn);
    g_set.fgColor    = scintillaFromColor(_fgWell.color);
    g_set.useBgColor = (_useBg.state == NSControlStateValueOn);
    g_set.bgColor    = scintillaFromColor(_bgWell.color);
    g_set.bold       = (_bold.state == NSControlStateValueOn);
    saveSettings();
    syncMenuChecks();
    applyMode();
}

- (void)ok:(id)s      { [self apply]; [NSApp stopModal]; }
- (void)cancel:(id)s  { [NSApp stopModal]; }
- (void)windowWillClose:(NSNotification *)n { [NSApp stopModal]; }

- (void)run {
    [self build];
    [_window center];
    [NSApp runModalForWindow:_window];
    [_window orderOut:nil];
}
@end

static void showSettings() {
    @autoreleasepool {
        CLNSettingsController *c = [[CLNSettingsController alloc] init];
        [c run];
    }
}

// ── plugin exports ───────────────────────────────────────────────────────────
extern "C" NPP_EXPORT void setInfo(NppData data) {
    nppData = data;
    loadSettings();

    memset(funcItem, 0, sizeof(funcItem));
    strncpy(funcItem[IDX_OFF]._itemName,      "Off (host numbers)", NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_OFF]._pFunc      = cmdOff;
    strncpy(funcItem[IDX_HEX]._itemName,      "Hexadecimal",    NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_HEX]._pFunc      = cmdHex;
    strncpy(funcItem[IDX_REL]._itemName,      "Relative",       NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_REL]._pFunc      = cmdRelative;
    strncpy(funcItem[IDX_DEC]._itemName,      "Decimal (custom start)", NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_DEC]._pFunc      = cmdDecimal;
    strncpy(funcItem[IDX_SETTINGS]._itemName, "Settings...",    NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_SETTINGS]._pFunc = showSettings;
    strncpy(funcItem[IDX_ABOUT]._itemName,    "About",          NPP_MENU_ITEM_SIZE - 1);
    funcItem[IDX_ABOUT]._pFunc    = showAbout;
    // No default shortcuts: host ignores FuncItem._pShKey, and Cmd-keys collide.
}

extern "C" NPP_EXPORT const char *getName() { return PLUGIN_NAME; }

extern "C" NPP_EXPORT FuncItem *getFuncsArray(int *nbF) { *nbF = nbFunc; return funcItem; }

extern "C" NPP_EXPORT void beNotified(SCNotification *n) {
    if (!n) return;
    switch (n->nmhdr.code) {
        case NPPN_READY:
            // Initial application of the persisted mode + reflect it in the menu.
            syncMenuChecks();
            applyMode();
            break;

        case NPPN_BUFFERACTIVATED:
            // A tab switch / freshly-opened buffer becomes active. The new buffer
            // has no margin text yet, and our margin config can be reset, so
            // re-establish and repaint. (Windows: DoNppnBufferActivated.)
            if (g_set.mode != kModeOff) {
                ensureMargin(currentScintilla());
                updateAllViews();
            }
            break;

        case NPPN_LANGCHANGED:
        case NPPN_DARKMODECHANGED:
            // Lexer/theme change can reset STYLE colors → re-copy host line-number
            // style into ours and repaint. (Windows: DoNppnLangChanged / DarkMode.)
            if (g_set.mode != kModeOff) {
                for (int v = 0; v < 2; ++v) configMarginStyle(viewHandle(v));
                updateAllViews();
            }
            break;

        case SCN_MODIFIED:
            // Repaint only when the line COUNT changed (insert/delete of lines),
            // mirroring CheckTextChanges (SCNotification.linesAdded ≠ 0).
            if (g_set.mode != kModeOff && n->linesAdded != 0)
                updateAllViews();   // both views: a cloned split shows the edit in each
            break;

        case SCN_UPDATEUI:
            // Caret move / scroll. Needed for relative mode (numbers shift with the
            // caret) and to fill the margin for newly-scrolled-in lines. Repaint
            // both views (each reads its own caret); the second handle is 0 when
            // there is no split, so this is one repaint in the common case.
            if (g_set.mode != kModeOff &&
                (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL | SC_UPDATE_CONTENT)))
                updateAllViews();
            break;

        case SCN_ZOOM:
            // Host re-fits margin-0 on zoom; we must re-fit ours and repaint too.
            if (g_set.mode != kModeOff) updateAllViews();
            break;

        default: break;
    }
}

extern "C" NPP_EXPORT intptr_t messageProc(uint32_t m, uintptr_t w, intptr_t l) {
    (void)m; (void)w; (void)l; return 1;
}
