"""Source contracts only; live rendering is verified separately on Omarchy."""
import pathlib
import unittest


class BreadIconContract(unittest.TestCase):
    def test_theme_aware_outline_replaces_disk_without_changing_actions(self):
        panel = (pathlib.Path(__file__).resolve().parents[1] / 'Panel.qml').read_text()
        button = panel.split('  BarIconButton {', 1)[1].split('  KeyboardPanel {', 1)[0]
        self.assertIn('iconComponent: Component', button)
        self.assertNotIn('󰆓', button)
        self.assertIn('button.active ? button.activeColor : button.foreground', button)
        self.assertIn('onInkChanged: requestPaint()', button)
        self.assertIn('c.stroke()', button)
        self.assertIn('c.scale(width / 24, height / 24)', button)
        self.assertIn('if (b === Qt.MiddleButton) refresh()', button)
        self.assertIn('else root.toggle()', button)


if __name__ == '__main__':
    unittest.main()
