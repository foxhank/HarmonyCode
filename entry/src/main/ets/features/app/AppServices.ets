import { GitClient } from '../../core/git/GitClient';
import { GitIdentity } from '../../core/git/GitTypes';
import { SettingsStore, settingsStore } from '../../core/settings/SettingsStore';

/** Supplies Git credentials from user settings without core/git depending on settings. */
class SettingsGitIdentity implements GitIdentity {
  private s: SettingsStore;

  constructor(s: SettingsStore) {
    this.s = s;
  }

  username(): string {
    return this.s.gitUsername;
  }

  token(): string {
    return this.s.gitToken();
  }

  authorName(): string {
    return this.s.authorName();
  }

  authorEmail(): string {
    return this.s.authorEmail();
  }
}

/** App-wide services shared by every screen. */
export class AppServices {
  static readonly git: GitClient = new GitClient(new SettingsGitIdentity(settingsStore));
}
