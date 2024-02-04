/* window.vala
 *
 * Copyright 2023 Leonhard
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Updater.MainWindow : Gtk.ApplicationWindow {
    private const string BACKUP_SUFFIX = "save";
    public const string APTD_DBUS_NAME = "org.debian.apt";
    public const string APTD_DBUS_PATH = "/org/debian/apt";

    private Gtk.Button button;

    private enum ProgressStep {
        PREPARING,
        UPDATING_REPOS,
        INSTALLING_UPDATES,
        FINISHED
    }

    private ProgressStep current_step;
    private Cancellable cancellable;
    private GenericSet<string> updated_repo_files;

    public MainWindow (Application app) {
        application = app;
    }

    construct {
        cancellable = new Cancellable ();
        updated_repo_files = new GenericSet<string> (str_hash, str_equal);

        current_step = PREPARING;

        button = new Gtk.Button.with_label ("start update");
        child = button;
        default_width = 500;
        default_height = 500;

        button.clicked.connect (() => {
            cancellable.reset ();
            button.sensitive = false;
            next ();
        });
    }

    private void next () {
        if (cancellable.is_cancelled ()) {
            return;
        }

        switch (current_step) {
            case PREPARING:
                current_step = UPDATING_REPOS;
                update_repo_files.begin ();
                break;

            case UPDATING_REPOS:
                current_step = INSTALLING_UPDATES;
                update_packages.begin ();
                break;

            case INSTALLING_UPDATES:
                current_step = FINISHED;
                next ();
                break;

            case FINISHED:
                button.label = "We are finished!";
                break;

            default:
                break;
        }
    }

    private void throw_fatal_error (Error? e = null, string? step = null) {
        cancellable.cancel ();
        revert_update_repos.begin ();
        if (e != null) {
            critical (step + e.message);
        }
    }

    private async void revert_update_repos () {
        foreach (var file_name in updated_repo_files.get_values ()) {
            try {
                var subprocess = new Subprocess (
                    STDERR_PIPE,
                    "pkexec",
                    "io.github.leolost2605.updater.system-upgrade-revert.helper",
                    file_name
                );
                var err_input_stream = subprocess.get_stderr_pipe ();

                yield subprocess.wait_async (null);

                if (subprocess.get_exit_status () != 0) {
                    uint8[] buffer = new uint8[100];
                    yield err_input_stream.read_async (buffer);
                    critical ("Helper failed to revert changes: %s", ((string)buffer));
                }
            } catch (Error e) {
                warning ("Failed to create subprocess: %s", e.message);
            }
        }
    }

    private async void update_repo_files () {
        var task = new Pk.Task ();
        try {
            var result = task.get_repo_list (0, null, () => {});

            if (result.get_exit_code () != SUCCESS) {
                throw_fatal_error (new IOError.FAILED ("FAILED TO GET REPOS"), "FAILED TO GET REPOS");
                return;
            }

            foreach (var repo in result.get_repo_detail_array ()) {
                if (cancellable.is_cancelled ()) {
                    return;
                }

                var parts = repo.repo_id.split (":", 2);
                if (parts[0] in updated_repo_files) {
                    continue;
                }

                updated_repo_files.add (parts[0]);

                yield update_repo_file ("jammy", "noble", parts[0]);
            }

            next ();
        } catch (Error e) {
            throw_fatal_error (e, "Getting Repo List");
        }
    }

    private async void update_repo_file (string old_codename, string new_codename, string path) {
        try {
            var subprocess = new Subprocess (
                STDERR_PIPE,
                "pkexec",
                "io.github.leolost2605.updatersystem-upgrade.helper",
                old_codename,
                new_codename,
                path
            );
            var err_input_stream = subprocess.get_stderr_pipe ();

            yield subprocess.wait_async (null);

            if (subprocess.get_exit_status () != 0) {
                uint8[] buffer = new uint8[100];
                yield err_input_stream.read_async (buffer);
                throw_fatal_error (new IOError.FAILED ((string)buffer), "Executing helper to update a repo file.");
            }
        } catch (Error e) {
            warning ("Failed to create subprocess: %s", e.message);
        }
    }

    private async void update_packages () {
        var task = new Pk.Task () {
            only_download = true,
            allow_downgrade = true,
            allow_reinstall = true
        };

        try {
            var refresh_result = yield task.refresh_cache_async (false, null, () => {});

            if (refresh_result.get_exit_code () != SUCCESS) {
                // throw_fatal_error (refresh_result.get_error_code (), "Refreshing apt cache.");
                return;
            }
        } catch (Error e) {
            throw_fatal_error (e, "Refreshing apt cache.");
            return;
        }

        yield upgrade_system ();

        //  try {
        //      var upgradable_packes_result = yield task.get_updates_async (0, null, () => {});
        //      string[] package_ids = {};
        //      foreach (var package in upgradable_packes_result.get_package_array ()) {
        //          package_ids += package.package_id;
        //      }

        //      yield task.update_packages_async (package_ids, null, (progress, type) => {
        //          if (type == PERCENTAGE) {
        //              button.label = "%i %".printf (progress.percentage);
        //          }
        //      });

        //      next ();
        //  } catch (Error e) {
        //      throw_fatal_error (e, "Updating packages.");
        //  }
    }

    private async void upgrade_system () {
        AptdService aptdaemon;
        try {
            aptdaemon = yield Bus.get_proxy (BusType.SYSTEM, APTD_DBUS_NAME, APTD_DBUS_PATH);
        } catch (GLib.Error e) {
            throw_fatal_error (e, "Getting aptdaemon");
            return;
        }

        string transaction_id = "";
        try {
            transaction_id = yield aptdaemon.upgrade_system (false);
        } catch (Error e) {
            throw_fatal_error (e, "Upgrade system");
            return;
        }

        AptdTransactionService transaction_proxy;
        try {
            transaction_proxy = yield Bus.get_proxy (BusType.SYSTEM, APTD_DBUS_NAME, transaction_id);
        } catch (GLib.Error e) {
            throw_fatal_error (e, "Getting transaction");
            return;
        }

        transaction_proxy.property_changed.connect ((prop, variant) => {
            string label;
            transaction_proxy.get ("status-details", out label);
            button.label = label;
        });

        transaction_proxy.finished.connect ((status) => {
            button.label = "Finished with status: " + status;
        });

        try {
            yield transaction_proxy.run ();
        } catch (Error e) {
            warning (e.message);
        }
    }
}
