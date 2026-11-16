/// Motif sûr à traduire sur la TV. Ne transporte jamais l'adresse fournisseur.
enum SourceImportProblem implements Exception {
  network, timeout, denied, webPage, empty, expired,
}
