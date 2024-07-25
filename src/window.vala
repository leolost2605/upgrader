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
    private const string APTD_DBUS_NAME = "org.debian.apt";
    private const string APTD_DBUS_PATH = "/org/debian/apt";

    public signal void state_changed ();

    private Gtk.Button button;

    public enum State {
        UP_TO_DATE,
        CHECKING,
        AVAILABLE,
        WORKING,
        RESTART_REQUIRED,
        ERROR
    }

    public struct CurrentState {
        State state;
        string status;
        int progress;
    }

    private enum ProgressStep {
        PREPARING,
        UPDATING_REPOS,
        REFRESHING,
        UPGRADING,
        FINALIZING
    }

    private CurrentState current_state;
    private ProgressStep current_step = PREPARING;
    private Cancellable cancellable;
    private GenericSet<string> updated_repo_files;
    private AptTransaction? transaction_proxy;

    public MainWindow (Application app) {
        application = app;
    }

    construct {
        cancellable = new Cancellable ();
        updated_repo_files = new GenericSet<string> (str_hash, str_equal);

        current_state = {
            AVAILABLE,
            "An upgrade to OS 8 is available",
            0
        };

        current_step = PREPARING;

        button = new Gtk.Button.with_label ("start update");
        child = button;
        default_width = 500;
        default_height = 500;

        button.clicked.connect (() => {
            start ();
            //  cancellable.reset ();
            //  button.sensitive = false;
            //  next ();
        });
    }

    private void start () {
        if (current_state.state != AVAILABLE) {
            return;
        }

        cancellable.reset ();
        next ();
    }

    private void next () {
        if (cancellable.is_cancelled ()) {
            return;
        }

        switch (current_step) {
            case PREPARING:
                update_state (WORKING, "Updating repository list");
                current_step = UPDATING_REPOS;
                update_repo_files.begin ();
                break;

            case UPDATING_REPOS:
                update_state (WORKING, "Refreshing cache");
                current_step = REFRESHING;
                refresh_cache.begin ();
                break;

            case REFRESHING:
                update_state (WORKING, "Upgrading system");
                current_step = UPGRADING;
                upgrade_system.begin ();
                break;

            case UPGRADING:
                update_state (WORKING, "Finalizing");
                current_step = FINALIZING;
                finalize_upgrade.begin ();
                break;

            case FINALIZING:
                button.label = "We are finished!";
                break;
        }
    }

    private void update_state (State state, string message = "", int progress = 0) {
        current_state = {
            state,
            message,
            progress
        };

        warning ("State updates: %s", message);

        state_changed ();
    }

    private void throw_fatal_error (Error? e = null, string? step = null) {
        cancellable.cancel ();
        revert_update_repos.begin ();
        if (e != null) {
            critical (step + e.message);
        }

        update_state (ERROR, e.message);
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

                Bytes stderr;
                yield subprocess.communicate_async (null, null, null, out stderr);

                var stderr_data = Bytes.unref_to_data (stderr);
                if (stderr_data != null) {
                    critical ("Helper failed to revert changes: %s", ((string)stderr_data));
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

    private async void refresh_cache () {
        var task = new Pk.Task ();

        try {
            yield task.refresh_cache_async (true, null, () => {});

            next ();
        } catch (Error e) {
            throw_fatal_error (e, "Refreshing apt cache.");
            return;
        }
    }

    private async void upgrade_system () {
        Apt aptdaemon;
        try {
            aptdaemon = yield Bus.get_proxy (BusType.SYSTEM, APTD_DBUS_NAME, APTD_DBUS_PATH);
        } catch (GLib.Error e) {
            throw_fatal_error (e, "Getting aptdaemon");
            return;
        }

        string transaction_id;
        try {
            transaction_id = yield aptdaemon.upgrade_system (false);
        } catch (Error e) {
            throw_fatal_error (e, "Upgrade system");
            return;
        }

        try {
            transaction_proxy = yield Bus.get_proxy (BusType.SYSTEM, APTD_DBUS_NAME, transaction_id);
        } catch (GLib.Error e) {
            throw_fatal_error (e, "Getting transaction");
            return;
        }

        transaction_proxy.property_changed.connect ((prop, variant) => {
            if (prop == "StatusDetails") {
                update_state (WORKING, (string) variant, current_state.progress);
            } else if (prop == "Progress") {
                update_state (WORKING, current_state.status, (int) variant);
            }
            warning ("prop changed: %s", prop);
        });

        transaction_proxy.finished.connect ((status) => {
            button.label = "Finished with status: " + status;
            transaction_proxy = null;
            next ();
        });

        try {
            yield transaction_proxy.run ();
        } catch (Error e) {
            warning (e.message);
        }
    }

    private async void finalize_upgrade () {
        yield install_systemd_resolved ();
        yield touch_network_config ();
    }

    private async void install_systemd_resolved () {
        var task = new Pk.Task ();
        Pk.Results results;
        try {
            results = yield task.search_names_async (Pk.Bitfield.from_enums (Pk.Filter.NONE), {"systemd-resolved"}, cancellable, () => {});
        } catch (Error e) {
            warning ("Failed to search for systemd-resolved: %s", e.message);
            return;
        }

        var package_ids = results.get_package_sack ().get_ids ();

        string? systemd_resolved_package = null;
        foreach (unowned var id in package_ids) {
            var split = id.split (";");
            if (split.length >= 1 && split[0] == "systemd-resolved") {
                systemd_resolved_package = id;
                break;
            }
        }

        try {
            yield task.install_packages_async ({systemd_resolved_package}, cancellable, () => {});
        } catch (Error e) {
            warning ("Failed to install systmed resolved: %s", e.message);
        }
    }

    private async void touch_network_config () {
        try {
            var subprocess = new Subprocess (
                STDERR_PIPE,
                "pkexec",
                "touch",
                "/etc/NetworkManager/conf.d/10-globally-managed-devices.conf"
            );
            var err_input_stream = subprocess.get_stderr_pipe ();

            yield subprocess.wait_async (null);

            if (subprocess.get_exit_status () != 0) {
                uint8[] buffer = new uint8[100];
                yield err_input_stream.read_async (buffer);
                throw_fatal_error (new IOError.FAILED ((string)buffer), "Touching network config.");
            }
        } catch (Error e) {
            warning ("Failed to create subprocess: %s", e.message);
        }
    }
}
