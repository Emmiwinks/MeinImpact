import 'package:flutter/material.dart';

/// The card-table world of the app ("Deine Hand"): a table the cards lie on,
/// light card stock, and four topic colours that rotate by topic so no
/// single (party-like) colour dominates.
@immutable
class MiColors extends ThemeExtension<MiColors> {
  const MiColors({
    required this.table,
    required this.tableRaised,
    required this.onTable,
    required this.onTableMuted,
    required this.cardStock,
    required this.onCard,
    required this.onCardMuted,
    required this.keyline,
    required this.shadow,
    required this.topics,
  });

  final Color table;
  // Sheets and rows that sit on the table (the "Alle" list, the card back's
  // fact chips).
  final Color tableRaised;
  final Color onTable;
  final Color onTableMuted;
  final Color cardStock;
  final Color onCard;
  final Color onCardMuted;
  // Hairline around cards and chips; carries the card edge on the light
  // table, where stock and table are close in value.
  final Color keyline;
  final Color shadow;
  // Coral, teal, amber, violet. Ink text sits on all four.
  final List<Color> topics;

  /// The filled button that lies on the table rather than on a card: it
  /// inverts the table (stock on ink, ink on peach). In a Row without
  /// Expanded, give it a finite minimumSize.
  ButtonStyle get tableButton => FilledButton.styleFrom(
        backgroundColor: onTable,
        foregroundColor: table,
        disabledBackgroundColor: onTable.withValues(alpha: 0.12),
        disabledForegroundColor: onTableMuted,
      );

  static const _ink = Color(0xFF101820);
  static const _stock = Color(0xFFF4F1EA);
  static const _topics = [
    Color(0xFFFF5A5F),
    Color(0xFF2EC4B6),
    Color(0xFFFFBF3C),
    Color(0xFF8C84FF),
  ];

  static const dark = MiColors(
    table: _ink,
    // Light enough to read as its own surface on the ink table.
    tableRaised: Color(0xFF243242),
    onTable: _stock,
    onTableMuted: Color(0xFFB9C0C8),
    cardStock: _stock,
    onCard: _ink,
    onCardMuted: Color(0xFF4A5560),
    keyline: Color(0x1FF4F1EA),
    shadow: Color(0x99000000),
    topics: _topics,
  );

  // A warm peach-cream table (the user's pick); cards a lighter warm white
  // so they still lift off it.
  static const light = MiColors(
    table: Color(0xFFFFF1E3),
    tableRaised: Color(0xFFFFF8F0),
    onTable: _ink,
    onTableMuted: Color(0xFF4A5560),
    cardStock: Color(0xFFFFFCF8),
    onCard: _ink,
    onCardMuted: Color(0xFF4A5560),
    keyline: Color(0x26101820),
    shadow: Color(0x33101820),
    topics: _topics,
  );

  @override
  MiColors copyWith({
    Color? table,
    Color? tableRaised,
    Color? onTable,
    Color? onTableMuted,
    Color? cardStock,
    Color? onCard,
    Color? onCardMuted,
    Color? keyline,
    Color? shadow,
    List<Color>? topics,
  }) =>
      MiColors(
        table: table ?? this.table,
        tableRaised: tableRaised ?? this.tableRaised,
        onTable: onTable ?? this.onTable,
        onTableMuted: onTableMuted ?? this.onTableMuted,
        cardStock: cardStock ?? this.cardStock,
        onCard: onCard ?? this.onCard,
        onCardMuted: onCardMuted ?? this.onCardMuted,
        keyline: keyline ?? this.keyline,
        shadow: shadow ?? this.shadow,
        topics: topics ?? this.topics,
      );

  @override
  MiColors lerp(MiColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MiColors(
      table: mix(table, other.table),
      tableRaised: mix(tableRaised, other.tableRaised),
      onTable: mix(onTable, other.onTable),
      onTableMuted: mix(onTableMuted, other.onTableMuted),
      cardStock: mix(cardStock, other.cardStock),
      onCard: mix(onCard, other.onCard),
      onCardMuted: mix(onCardMuted, other.onCardMuted),
      keyline: mix(keyline, other.keyline),
      shadow: mix(shadow, other.shadow),
      topics: [
        for (var i = 0; i < topics.length; i++) mix(topics[i], other.topics[i]),
      ],
    );
  }
}

extension MiThemeContext on BuildContext {
  MiColors get mi => Theme.of(this).extension<MiColors>()!;
}

abstract final class MiFonts {
  static const display = 'Unbounded';
  static const text = 'AlbertSans';
}

/// 4dp grid.
abstract final class MiSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class MiRadius {
  static const double card = 26;
  static const double chip = 999;
  static const double tile = 14;
}

abstract final class MiMotion {
  static const quick = Duration(milliseconds: 160);
  static const settle = Duration(milliseconds: 280);
  static const flip = Duration(milliseconds: 300);
  static const flight = Duration(milliseconds: 520);
  static const ease = Curves.easeOutQuart;

  /// True when the system asks for no animations: every motion becomes an
  /// instant cut.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

ThemeData miTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? MiColors.dark : MiColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: colors.topics[2],
    brightness: brightness,
  ).copyWith(
    surface: colors.table,
    onSurface: colors.onTable,
    onSurfaceVariant: colors.onTableMuted,
    primary: colors.onTable,
    onPrimary: colors.table,
    secondaryContainer: colors.topics[2],
    onSecondaryContainer: colors.onCard,
    outline: colors.keyline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: MiFonts.text,
  );
  final text = base.textTheme.apply(
    bodyColor: colors.onTable,
    displayColor: colors.onTable,
  );
  TextStyle display(TextStyle? style, double size) => style!.copyWith(
        fontFamily: MiFonts.display,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.02 * size,
      );
  final muted = TextStyle(
    fontFamily: MiFonts.text,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: colors.onTableMuted,
  );
  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(MiRadius.tile),
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    scaffoldBackgroundColor: colors.table,
    extensions: [colors],
    textTheme: text.copyWith(
      headlineMedium: display(text.headlineMedium, 28),
      titleLarge: display(text.titleLarge, 21),
      titleMedium: text.titleMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      bodyLarge: text.bodyLarge!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyMedium: text.bodyMedium!.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelLarge: text.labelLarge!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: text.labelMedium!.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.table,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.topics[2],
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: MiFonts.text,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? colors.onTable
              : colors.onTableMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.onCard
              : colors.onTableMuted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.onCard,
        foregroundColor: colors.cardStock,
        minimumSize: const Size.fromHeight(52),
        // Room above and below a label that wraps at large text sizes.
        padding: const EdgeInsets.symmetric(
          horizontal: MiSpace.lg,
          vertical: MiSpace.md,
        ),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: MiFonts.text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.onTable,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: MiFonts.text,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    // Secondary steps on the table ("Kopieren", "Fragebogen ausfüllen").
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onTable,
        side: BorderSide(color: colors.onTableMuted),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(
          horizontal: MiSpace.lg,
          vertical: MiSpace.md,
        ),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: MiFonts.text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.topics[2],
      selectionColor: colors.topics[2].withValues(alpha: 0.4),
      selectionHandleColor: colors.topics[2],
    ),
    // Pushed screens (letter, browser, "Alle Aktionen") lie on the table.
    appBarTheme: AppBarTheme(
      backgroundColor: colors.table,
      foregroundColor: colors.onTable,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: display(text.titleLarge, 21),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.tableRaised,
      labelStyle: muted,
      floatingLabelStyle: muted.copyWith(fontWeight: FontWeight.w700),
      hintStyle: muted,
      helperStyle: muted.copyWith(fontSize: 13),
      counterStyle: muted.copyWith(fontSize: 13),
      border: field(colors.keyline),
      enabledBorder: field(colors.keyline),
      disabledBorder: field(colors.keyline),
      focusedBorder: field(colors.onTableMuted, 1.5),
    ),
    // Ticked is "selected": amber with an ink check.
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.topics[2]
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(colors.onCard),
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? BorderSide(color: colors.topics[2], width: 2)
            : BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? colors.keyline
                    : colors.onTableMuted,
                width: 2,
              ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: colors.onTable,
      collapsedIconColor: colors.onTableMuted,
      textColor: colors.onTable,
      collapsedTextColor: colors.onTable,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.onTable,
      linearTrackColor: colors.keyline,
    ),
    // Inverts the table, like the buttons on it.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.onTable,
      contentTextStyle: TextStyle(
        fontFamily: MiFonts.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colors.table,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiRadius.tile),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.tableRaised,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyLarge,
      labelTextStyle: WidgetStatePropertyAll(text.bodyLarge),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MiRadius.tile),
        side: BorderSide(color: colors.keyline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.table,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: colors.onTableMuted,
    ),
  );
}
