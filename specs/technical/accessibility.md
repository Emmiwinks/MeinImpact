# Accessibility

## Purpose
Defines accessibility requirements across all UI components. These are
first-class requirements, not afterthoughts. Every feature spec
references this document.

---

## Decisions

- **WCAG 2.1 AA is the baseline standard.** All UI components must
  meet AA criteria as a minimum.

- **Flutter Semantics are used throughout.** Every interactive element
  has a Semantics widget with a meaningful label. No unlabelled icons.

- **Three settings are user-configurable:** font size, high contrast,
  reduced motion. All stored in Hive `settings` box.

- **Accessibility is tested on real devices,** not only via automated
  tools. TalkBack (Android) and VoiceOver (iOS) must be tested before
  each release.

---

## Colour and Contrast

### Brand colour usage

| Element | Foreground | Background | Ratio | WCAG |
|---|---|---|---|---|
| Primary button text | #FFFFFF | #1D9E75 | 3.2:1 | AA (large text) |
| Body text | #1A1A1A | #FFFFFF | 16.8:1 | AAA |
| Secondary text | #666666 | #FFFFFF | 5.7:1 | AA |
| Tertiary text | #888888 | #FFFFFF | 3.5:1 | AA (large text only) |
| Success green text | #0F6E56 | #E8F7F2 | 4.6:1 | AA |
| Amber badge text | #854F0B | #FEF3E2 | 4.8:1 | AA |

**Note:** The primary button (#1D9E75 on white) at small text does not
meet AA (requires 4.5:1). Primary buttons must use minimum 16sp text.

### High contrast mode
When `settings.high_contrast = true`:
- All borders increase to minimum 2px
- Background fills are replaced with white (#FFFFFF)
- Tertiary text (#888888) upgrades to secondary (#666666)
- Brand green text uses dark variant (#085041)

```dart
class AppTheme {
  static ThemeData theme(bool highContrast) {
    return ThemeData(
      colorScheme: highContrast
          ? _highContrastScheme
          : _defaultScheme,
    );
  }
}
```

---

## Font Size

Three size options in Settings → Darstellung:

| Option | Base text | Body | Notes |
|---|---|---|---|
| Normal | 14sp | 16sp | Default |
| Groß | 17sp | 19sp | +3sp across all text |
| Sehr groß | 20sp | 22sp | +6sp across all text |

Implementation via Flutter's `textScaleFactor`:

```dart
// Respect system font scale, cap at 2.0 to prevent layout breaks
MediaQuery(
  data: MediaQuery.of(context).copyWith(
    textScaleFactor: min(
      MediaQuery.of(context).textScaleFactor,
      2.0,
    ),
  ),
  child: child,
)
```

---

## Minimum Touch Targets

All interactive elements: minimum **48 × 48 dp**.

Small elements (inline links, toggle switches) use `Padding` or
`GestureDetector` with a larger hit area while keeping visual size.

```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Container(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    child: SmallIcon(),
  ),
)
```

---

## Screenreader Support

### Semantics labels

Every interactive element must have a Semantics label:

```dart
// Action card
Semantics(
  label: '${action.title}. ${action.urgencyLabel}. '
         '${action.actionTypeLabel}. Ungefähr ${action.timeEstimate}.',
  button: true,
  child: ActionCard(action: action),
)

// Streak display
Semantics(
  label: 'Aktuelle Serie: ${streak} Wochen in Folge.',
  child: StreakBadge(streak: streak),
)

// Relevance dots
Semantics(
  label: 'Relevanz für dich: ${filledDots} von 5.',
  excludeSemantics: true,  // Children (dots) excluded
  child: RelevanceDots(filled: filledDots),
)

// Letter draft (streaming)
Semantics(
  label: isStreaming
      ? 'Brief wird erstellt...'
      : 'Brief-Entwurf: $draftText',
  liveRegion: true,  // Announce updates to screenreader
  child: DraftTextWidget(text: draftText),
)
```

### Live regions

Elements that change dynamically must use `liveRegion: true`:
- Streaming letter text
- Completion count updates
- Error states

### Focus management

After opening a new screen, focus moves to the first interactive element
or the screen title. Avoid focus traps. Modal bottom sheets return focus
to the trigger element on close.

---

## Reduced Motion

When `settings.reduced_motion = true` or system reduced motion is enabled:

- Streaming text appears all at once (no typewriter animation)
- Badge award animation is instant (no scale/fade)
- Page transitions use simple fade instead of slide
- No looping animations anywhere

```dart
bool get reducedMotion =>
    MediaQuery.of(context).disableAnimations ||
    Hive.box('settings').get('reduced_motion', defaultValue: false);
```

---

## Keyboard and Switch Access

For web and Android keyboard navigation:

- All interactive elements are reachable via Tab key
- Focus order follows visual reading order (top-to-bottom, left-to-right)
- Enter/Space activates buttons
- Escape closes modals and bottom sheets
- No keyboard traps

Slider (value profile):
```dart
Semantics(
  label: '${questionLabel}. Aktueller Wert: ${valueLabel}.',
  slider: true,
  value: valueLabel,
  increasedValue: increaseLabel,
  decreasedValue: decreaseLabel,
  onIncrease: () => setValue(value + 1),
  onDecrease: () => setValue(value - 1),
  child: CustomSlider(...),
)
```

---

## Specific Component Requirements

### Feed card
- Full card is one focusable element (not individual sub-elements)
- Label includes: title, type, urgency, time estimate
- Swipe-to-dismiss available via long-press menu for switch access

### Value profile sliders
- Each slider: keyboard-operable with step size 1
- Both poles labelled and read by screenreader
- Current position announced on change

### Action confirmation modal
- Trap focus within modal until dismissed
- "Ja" / "Nein" both accessible via keyboard
- Escape = "Nein" / cancel

### Streaming letter draft
- `liveRegion: true` so screenreader announces tokens as they arrive
- In reduced motion: entire text announced once on completion
- "Anpassen" button labelled: "Brief bearbeiten"

### Tracking timeline
- Semantic list structure (`role="list"`)
- Each event: date + outcome + description in label
- Status icons have text equivalents in semantics

### Settings sliders (font size)
- Three discrete options, not a continuous slider
- Selected option has `selected: true` in Semantics

---

## Testing Checklist

Before each release:

- [ ] TalkBack (Android): navigate full onboarding with eyes closed
- [ ] VoiceOver (iOS): navigate feed and complete one action
- [ ] Large font (200% system scale): no text truncation or overflow
- [ ] High contrast: all text meets AA
- [ ] Keyboard (web): full navigation without mouse
- [ ] Reduced motion: no animations play
- [ ] Colour blindness sim (Sim Daltonism): no info conveyed by colour only

---

## Dependencies

- Reads: `architecture/overview.md`
- Referenced by: all `features/` specs, `user/onboarding.md`

---

## Open Questions

- None.
