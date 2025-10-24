local _, addonTable = ...
local L = addonTable.L

addonTable.WEIGHT_HIT_LABEL = "Treff."
addonTable.RESULT_HIT_LABEL = "Trefferwert"
addonTable.STAT_DODGE_LABEL = "Ausw."
addonTable.STAT_MASTERY_LABEL = "Meisters."

L["%s does not match your currently equipped %s. ReforgeLite only supports equipped items."] = "%s stimmt nicht mit Ihrem aktuell ausgerüsteten %s überein. ReforgeLite unterstützt nur ausgerüstete Gegenstände."
L["%s does not match your currently equipped %s: %s. ReforgeLite only supports equipped items."] = "%s stimmt nicht mit Ihrem aktuell ausgerüsteten %s überein: %s. ReforgeLite unterstützt nur ausgerüstete Gegenstände."
L["^+(%d+) %s$"] = "^+(%d+) %s$"
L["Active window color"] = "Aktive Fensterfarbe"
L["Add cap"] = "Neues Cap"
--[[Translation missing --]]
--[[ L["Apply %s Output"] = ""--]] 
L["At least"] = "Mindestens"
L["At most"] = "Maximal"
--[[Translation missing --]]
--[[ L["Bearweave"] = ""--]]
L["Best Result"] = "Bestes Resultat"
L["Alt %d"] = "Alt %d"
L["Alternative %d"] = "Alternative %d"
L["Alternative results to display"] = "Anzahl alternativer Resultate"
L["All caps satisfied"] = "Alle Caps erfüllt"
L["Caps not met"] = "Caps nicht erreicht"
--[[Translation missing --]]
--[[ L["Buffs"] = ""--]]
L["Cap value"] = "Capwert tooltip"
L["Click an item to lock it"] = "Klicken um einen Gegenstand zu sperren"
L["Compute"] = "Berechnen"
L["Crit block"] = "Kritischer Block"
--[[Translation missing --]]
--[[ L["Debug"] = ""--]] 
--[[Translation missing --]]
--[[ L["Destination stat color"] = ""--]] 
L["Enable spec profiles"] = "Spezialisierungsprofile aktivieren"
--[[Translation missing --]]
--[[ L["Enter pawn string"] = ""--]] 
L["Enter the preset name"] = "Gib den Preset-Namen ein"
L["Enter WoWSims JSON"] = "WoWSims-JSON eingeben"
L["Enter WoWSims JSON or Pawn string"] = "WoWSims-JSON oder Pawn-String eingeben"
L["Enter a number between %d and %d."] = "Gib eine Zahl zwischen %d und %d ein."
L["Exactly"] = "Genau"
L["Expertise hard cap"] = "Waffenkunde Hardcap"
L["Expertise soft cap"] = "Waffenkunde Softcap"
L["Export"] = "Export"
--[[Translation missing --]]
--[[ L["Highlight reforged stats"] = ""--]] 
L["Import"] = "Import"
L["Import WoWSims/Pawn/QE"] = "Import WoWSims/Pawn/QE"
L["Inactive window color"] = "inaktive Fensterfarbe"
--[[Translation missing --]]
--[[ L["Masterfrost"] = ""--]] 
L["Melee DW hit cap"] = "Nahkampf mit zwei Einhandwaffen Treffercap"
L["Melee hit cap"] = "Nahkampf Hit Cap einstellen"
--[[Translation missing --]]
--[[ L["Monocat"] = ""--]] 
L["No reforge"] = "Kein Umschieden"
L["Open window when reforging"] = "Fenster öffnen zum Umschmieden"
--[[Translation missing --]]
--[[ L["Other/No flask"] = ""--]]
--[[Translation missing --]]
--[[ L["Other/No food"] = ""--]]
--[[Translation missing --]]
--[[ L["Presets"] = ""--]]
L["Click to load preset"] = "Klicken, um das Preset zu laden"
L["Shift+Click to delete"] = "Shift+Klick zum Löschen"
L["Delete preset '%s'?"] = "Preset '%s' löschen?"
L["Reforging window must be open"] = "Umschmieden Fenster muss geöffnet sein"
L["Remove cap"] = "Entferne Cap"
L["Result"] = "Resultat"
L["Score"] = "Punkte"
L["Show reforged stats in item tooltips"] = "Zeige umgeschmiedete Werte im Gegenstandstooltip"
L["Show import button"] = "Import-Schaltfläche anzeigen"
L["Show help buttons"] = "Hilfeschaltflächen anzeigen"
L["Slide to the left if the calculation slows your game too much."] = "Schieben Sie es nach links, wenn die Berechnung Ihr Spiel zu sehr verlangsamt."
L["Speed/Accuracy"] = "Geschwindigkeit/Genauigkeit"
L["Extra Fast"] = "Extra schnell (am ungenauesten)"
L["Fast"] = "Schnell (reduzierte Genauigkeit)"
L["Normal"] = "Normal (höchste Genauigkeit)"
--[[Translation missing --]]
--[[ L["Source stat color"] = ""--]]
L["Pawn successfully imported."] = "Pawn erfolgreich importiert."
L["Spell Haste"] = "Zaubertempo"
L["This import is missing player equipment data! Please make sure \"Gear\" is selected when exporting from WoWSims."] = "Dieser Import enthält keine Ausrüstungsdaten! Bitte stellen Sie sicher, dass beim WoWSims-Export \"Gear\" ausgewählt ist."
L["Spell hit cap"] = "Zaubertrefferwertungscap"
L["Spirit to hit"] = "Willenskraft in Trefferwertung"
L["Stat Weights"] = "Gewichtung"
L["Sum"] = "Summe"
L["Summarize reforged stats"] = "Umschmiede-Werte zusammenfassen"
--[[Translation missing --]]
--[[ L["Tanking model"] = ""--]]
--[[Translation missing --]]
--[[ L["ticks"] = ""--]]
L["Weight after cap"] = "Gewichtung über Cap"
--[[Translation missing --]]
--[[ L["Window Settings"] = ""--]]

L["The Item Table shows your currently equipped gear and their stats.\n\nEach row represents one equipped item. Only stats present on your gear are shown as columns.\n\nAfter computing, items being reforged show:\n• Red numbers: Stat being reduced\n• Green numbers: Stat being added\n\nClick an item icon to lock/unlock it. Locked items (shown with a lock icon) are ignored during optimization."] = "Die Gegenstandstabelle zeigt deine aktuell ausgerüsteten Gegenstände und deren Werte.\n\nJede Zeile steht für einen ausgerüsteten Gegenstand. Als Spalten werden nur Werte angezeigt, die auf deiner Ausrüstung vorkommen.\n\nNach der Berechnung zeigen umgeschmiedete Gegenstände:\n• Rote Zahlen: Wert, der verringert wird\n• Grüne Zahlen: Wert, der erhöht wird\n\nKlicke auf das Symbol eines Gegenstands, um ihn zu sperren oder zu entsperren. Gesperrte Gegenstände (erkennbar am Schloss-Symbol) werden bei der Optimierung ignoriert."
L["The Result table shows the stat changes from the optimized reforge.\n\nThe left column shows your total stats after reforging.\n\nThe right column shows how much each stat changed:\n- Green: Stat increased and improved your weighted score\n- Red: Stat decreased and lowered your weighted score\n- Grey: No meaningful change (either unchanged, or changed but weighted score stayed the same)\n\nClick 'Show' to see a detailed breakdown of which items to reforge.\n\nClick 'Reset' to clear the current reforge plan."] = "Die Ergebnistabelle zeigt die Wertänderungen der optimierten Umschmiedung.\n\nDie linke Spalte zeigt deine Gesamtwerte nach dem Umschmieden.\n\nDie rechte Spalte zeigt, wie stark sich jeder Wert verändert hat:\n- Grün: Wert wurde erhöht und verbessert deine Gewichtungspunktzahl\n- Rot: Wert wurde verringert und senkt deine Gewichtungspunktzahl\n- Grau: Keine nennenswerte Veränderung (entweder unverändert oder verändert, ohne dass sich die Punktzahl geändert hat)\n\nKlicke auf \"Anzeigen\", um eine detaillierte Übersicht zu erhalten, welche Gegenstände umgeschmiedet werden.\n\nKlicke auf \"Zurücksetzen\", um den aktuellen Umschmiedeplan zu löschen."
L["|cffffffffPresets:|r Load pre-configured stat weights and caps for your spec. Click to select from class-specific presets, custom saved presets, or Pawn imports.\n\n|cffffffffImport:|r Use stat weights from WoWSims, Pawn, or QuestionablyEpic. WoWSims and QE can also import pre-calculated reforge plans.\n\n|cffffffffTarget Level:|r Select your raid difficulty to calculate stat caps at the appropriate level (PvP, Heroic Dungeon, or Raid).\n\n|cffffffffBuffs:|r Enable raid buffs you'll have active (Spell Haste, Melee Haste, Mastery) to account for their stat bonuses in cap calculations.\n\n|cffffffffStat Weights:|r Assign relative values to each stat. Higher weights mean the optimizer will prioritize that stat more when reforging. For example, if Hit has weight 60 and Crit has weight 20, the optimizer values Hit three times more than Crit.\n\n|cffffffffStat Caps:|r Set minimum or maximum values for specific stats. Use presets (Hit Cap, Expertise Cap, Haste Breakpoints) or enter custom values. The optimizer will respect these caps when calculating the optimal reforge plan."] = "|cffffffffVoreinstellungen:|r Lade vorkonfigurierte Wertungsgewichte und Caps für deine Spezialisierung. Klicke, um aus klassenspezifischen Voreinstellungen, eigenen gespeicherten Voreinstellungen oder Pawn-Importen zu wählen.\n\n|cffffffffImport:|r Verwende Wertungsgewichte aus WoWSims, Pawn oder QuestionablyEpic. WoWSims und QE können auch vorkalkulierte Umschmiedepläne importieren.\n\n|cffffffffZielstufe:|r Wähle deine Schlachtzugs-Schwierigkeit, um Wertungs-Caps für das passende Niveau zu berechnen (PvP, heroische Dungeons oder Schlachtzug).\n\n|cffffffffStärkungszauber:|r Aktiviere Schlachtzugs-Buffs, die du aktiv haben wirst (Zaubertempo, Nahkampftempo, Meisterschaft), damit ihre Werte in die Cap-Berechnungen einfließen.\n\n|cffffffffWertungsgewichte:|r Weise jedem Wert einen relativen Wert zu. Höhere Gewichte bedeuten, dass der Optimierer diesen Wert beim Umschmieden stärker priorisiert. Wenn Trefferwertung beispielsweise Gewicht 60 und Kritische Trefferwertung Gewicht 20 hat, bewertet der Optimierer Trefferwertung dreimal so hoch wie Kritische Trefferwertung.\n\n|cffffffffWertungs-Caps:|r Lege Mindest- oder Höchstwerte für bestimmte Werte fest. Nutze Voreinstellungen (Treffer-Cap, Waffenkunde-Cap, Tempogrenzen) oder gib eigene Werte ein. Der Optimierer berücksichtigt diese Caps bei der Berechnung des optimalen Umschmiedeplans."
L["Your Expertise rating is being converted to spell hit.\n\nIn Mists of Pandaria, casters benefit from Expertise due to it automatically converting to Hit at a 1:1 ratio.\n\nThe Hit value shown above includes this converted Expertise rating.\n\nNote: The character sheet is bugged and doesn't show Expertise converted to spell hit, but the conversion works correctly in combat."] = "Deine Waffenkundewertung wird in Zaubertrefferwertung umgewandelt.\n\nIn Mists of Pandaria profitieren Zauberwirker von Waffenkunde, da sie automatisch im Verhältnis 1:1 in Trefferwertung umgewandelt wird.\n\nDer oben angezeigte Trefferwert enthält diese umgewandelte Waffenkundewertung.\n\nHinweis: Das Charakterfenster ist fehlerhaft und zeigt die in Zaubertreffer umgewandelte Waffenkunde nicht an, aber die Umwandlung funktioniert im Kampf korrekt."

