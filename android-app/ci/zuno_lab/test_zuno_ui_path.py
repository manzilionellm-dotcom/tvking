"""États de l’UI issus des libellés de ZUNO 119 dans app_en/fr.arb. Tests du pilote."""
import unittest
from zuno_ui_path import next_step


def surface(*labels):
    return [(label, 200, 50 * (i + 1), "android.view.View") for i, label in enumerate(labels)]


class Navigation(unittest.TestCase):
    def test_hub_then_manager_then_form(self):
        def decide(names, phase):
            return next_step(surface(*names), [], (1920,1080), phase)[0]
        self.assertEqual(decide(["Live","Movies","Server"],"choose"), "server")
        self.assertEqual(decide(["Live","Movies","Settings"],"choose"), "settings")
        self.assertEqual(decide(["Settings","My sources (add / activate / delete)","Sources"],"choose"), "settings-sources")
        self.assertEqual(decide(["My sources","Add M3U","Add Xtream"],"choose"), "add-m3u")
        nodes = surface("Add my source","Paste","File","M3U / URL")
        nodes.append(("M3U URL", 300, 500, "android.widget.EditText"))
        self.assertEqual(next_step(nodes,[],(1920,1080),"url"), ("type-url",(300,500)))
        self.assertEqual(decide(["My sources","My list","2 channels"],"after-submit"),"return-to-hub")
        self.assertEqual(decide(["Movies","Live","Settings"],"after-submit"),"live")
        self.assertEqual(decide(["Mire B","Mire A"],"after-submit"),"channel-a")

    def test_inline_xtream_form_never_receives_m3u_in_server_field(self):
        ns = surface("Add my source","Paste","File","M3U / URL")
        ns += [(name,200,400+i*80,"android.widget.EditText")
               for i,name in enumerate(["Server","Username","Password"])]
        self.assertEqual(next_step(ns,[],(1280,720),"choose")[0], "choose-m3u")
        self.assertEqual(next_step(ns,[],(1280,720),"url")[0], "wait")

    def test_ocr_requires_channel_letter_on_its_own_line(self):
        words=[("mire",400,120),("b",450,120),("mire",400,190),("a",450,190)]
        self.assertEqual(next_step([],words,(1280,720),"after-submit"),("channel-a",(425,190)))
        self.assertEqual(next_step([],words[:2],(1280,720),"after-submit")[0],"wait")
        self.assertEqual(next_step([],words[:-1]+[("a",450,500)],(1280,720),"after-submit")[0],"wait")

    def test_french_and_wrong_surface(self):
        self.assertEqual(next_step(surface("Mes sources","Ajouter M3U","Ajouter Xtream"),[],(1280,720),"choose")[0],"add-m3u")
        self.assertEqual(next_step(surface("Contact","Server 123","M3U provider"),[],(1280,720),"choose")[0],"wait")

    def test_submit_only_in_matching_form(self):
        self.assertEqual(next_step(surface("Add my source","Sign in and load"),[],(1280,720),"after-submit")[0],"submit-button")
        self.assertEqual(next_step(surface("Sign in and load","My bank"),[],(1280,720),"after-submit")[0],"wait")

if __name__ == "__main__":
    unittest.main()
