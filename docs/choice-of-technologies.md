# Choice of Technologies

> Note (2026-09): this document reflects the original technology planning. The
> line marked "not used" below was an early consideration that didn't make it
> into the shipped app - see `CLAUDE.md` for what's actually in use today.

# Flutter (Frontend)
- Flutter wird verwendet, um das Frontend der App zu entwickeln
- Mit Flutter kann eine ansprechende und konsistente Benutzeroberfläche erstellt werden, die auf verschiedenen Geräten und Plattformen reibungslos läuft. Die plattformübergreifende Verwendung von Flutter ermöglicht es Zeit und Ressourcen zu sparen, indem eine einzige Codebasis für iOS und Android verwendet werden kann

# Firebase (Backend Services) - **not used**
- Ursprünglich für Backend-Services (Benutzerkonten, Einstellungs-Sync, Weckerspeicherung) in Betracht gezogen. Tatsächlich umgesetzt wurde stattdessen eine vollständig lokale, offline-fähige App ohne jegliche Netzwerkkommunikation (siehe `CLAUDE.md`) - Firebase kommt nirgends zum Einsatz.