# Physical mouse checks

Open `TestPage.html` locally in your browser with the app enabled and Accessibility allowed.

1. Middle-click ordinary text in the long page. Move away from the anchor: the page should scroll and the physical pointer should remain free. Move back to pause; press Esc to stop.
2. Middle-click the example link, including its bold child text. It should open a new tab without starting autoscroll. Middle-click that tab to close it, where the browser supports this action.
3. Start over text inside the nested panel. Check vertical and horizontal scrolling, then stop. The original panel should remain the target as the pointer moves.
4. Middle-click the text field and custom control. No anchor should appear. The custom control's native-click count should increase.
5. Start scrolling, then click a link. The click should stop scrolling without opening the link. The next middle click should work normally.
6. Test app switching, wheel input, keyboard input, pause, and app exclusions. Each should stop autoscroll as appropriate.
7. Test a native app with scrollable content, such as Preview. Note any native-click fallback reported by Diagnostics.
8. With your mouse remapper running, verify your existing side-button and button-combination gestures while autoscroll is inactive. The first click during active autoscroll is reserved for stopping it.

9. Toggle Start at login on, quit and reopen the app, and confirm the switch still reflects macOS registration. Toggle it off to unregister. An actual sign-out/sign-in is a separate manual check.
10. Toggle Show in Dock off and on. Reopen Settings from the Dock, then open Options and confirm speed, exclusions, and Quit remain reachable without the status icon.
11. Check all four combinations of Show in Dock and Show in Menu Bar. With both off, close Settings and open the app again from Finder or Spotlight. Settings must appear with both switches still off. Repeat after quitting and relaunching. Restore your preferred visibility settings afterward.

The input engine was physically verified in Arc on Apple Silicon before the public UI cleanup. The public build's automated checks and universal compilation do not establish compatibility with every app or Intel hardware.
