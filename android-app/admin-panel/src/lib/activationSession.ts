// Une activation peut débiter le revendeur. Si l'envoi des listes échoue
// ensuite, on reprend uniquement cet envoi, jamais l'activation payante.
export class ActivationSession<L, S> {
  license: L | null = null;
  sources: S | null = null;
  private work: Promise<void> | null = null;
  private licenseAttempted = false;

  private readonly operations: {
    activate: () => Promise<L>;
    sendSources?: () => Promise<S>;
    onLicense: (license: L) => void;
    onSources?: (sources: S) => void;
  };

  constructor(operations: ActivationSession<L, S>['operations']) {
    this.operations = operations;
  }

  run(): Promise<void> {
    if (this.work) return this.work;
    this.work = this.complete().finally(() => { this.work = null; });
    return this.work;
  }

  private async complete() {
    if (!this.license) {
      if (this.licenseAttempted) {
        throw new Error('Résultat de l’activation incertain. Vérifiez la fiche appareil avant une nouvelle activation.');
      }
      this.licenseAttempted = true;
      this.license = await this.operations.activate();
      this.operations.onLicense(this.license);
    }
    if (this.operations.sendSources && !this.sources) {
      this.sources = await this.operations.sendSources();
      this.operations.onSources?.(this.sources);
    }
  }
}
