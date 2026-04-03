# Code Audit Report

**Date**: 2026-04-03
**Project**: MusyncMIMO
**Auditor**: Pepito (OpenWork)
**Version**: 0.1.34

## Executive Summary

Audit complet du codebase MusyncMIMO (~8,500 lignes, 43 fichiers .dart).
Score global : 62/100

| Severity | Count |
|----------|-------|
| 🔴 Critical | 6 |
| 🟠 High | 10 |
| 🟡 Medium | 12 |
| 🟢 Low | 6 |
| ℹ️ Info | 4 |

## Critical Findings (Fixed in v0.1.34)

### CRIT-001 — Fuite mémoire _stateSub dans PlayerBloc ✅ FIXÉ
- `_stateSub` écrasé 2 fois → subscription jamais annulée
- Fix : cancel avant réassignation

### CRIT-002 — getLatestSnapshot ne désérialise pas JSON ✅ FIXÉ
- Retournait JSON brut au lieu de SessionContext
- Fix : désérialisation via SessionContext.fromJson()

### CRIT-003 — DRY : extractFileName() dupliqué 8 fois ✅ FIXÉ
- Pattern `path.split('/').last.split('\\').last` extrait en utilitaire
- Fix : fonction `extractFileName()` dans `core/utils/format.dart`

### CRIT-004 — God Object session_manager.dart (1317 lignes) ⚠️ NON FIXÉ
- Orchestre trop de responsabilités
- Plan : découper en Sprint 2

### CRIT-005 — Validation messages WebSocket ✅ FIXÉ
- Pas de limite de taille → risque OOM
- Fix : maxMessageSizeBytes = 1MB

### CRIT-006 — Sanitization noms de fichiers ✅ FIXÉ
- Path traversal possible dans file_transfer_service
- Fix : regex sanitization

## High Priority Findings

### HIGH-001 — 13 fichiers > 300 lignes ⚠️ NON FIXÉ
### HIGH-002 — ~13 fonctions > 50 lignes ⚠️ NON FIXÉ
### HIGH-003 — Couplage fort PlayerBloc → SessionManager ⚠️ NON FIXÉ
### HIGH-004 — 18 catch (_) silencieux ✅ FIXÉ (partiellement)

## Security Findings

### SEC-001 — Clés Firebase dans le repo ⚠️ .gitignore mis à jour
### SEC-002 — badCertificateCallback = true ⚠️ Documenté, fix planifié
### SEC-003 — Pas d'authentification WebSocket ⚠️ Planifié (SÉCURITÉ 2)

## Recommended Action Plan

### Sprint 1 (Immédiat) ✅ FAIT
- Fix fuites mémoire
- Fix validation input
- Fix DRY violations critiques
- Mise à jour .gitignore

### Sprint 2 (Semaine prochaine)
- Découper SessionManager
- Réduire fichiers > 300 lignes
- Authentification WebSocket (JWT)

### Sprint 3 (Mois 1-2)
- Interface PlaybackService
- Centraliser seuils sync quality
- Tests d'intégration
