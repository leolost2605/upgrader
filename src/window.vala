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
    private Gtk.Button button;

    public MainWindow (Application app) {
        application = app;
    }

    construct {
        button = new Gtk.Button.with_label ("start update");
        child = button;
        default_width = 500;
        default_height = 500;

        button.clicked.connect (() => start_update.begin());
    }

    private async void start_update () throws Error {
        var task = new Pk.Task () {
            only_download = true
        };

        try {

            var results = task.get_repo_list (0, null, () => {});

            var updated_files = new GenericSet<string> (str_hash, str_equal);
            foreach (var repo in results.get_repo_detail_array ()) {
                var parts = repo.repo_id.split (":", 2);
                if (parts[0] in updated_files) {
                    continue;
                }

                updated_files.add (parts[0]);

                var file = File.new_for_path (parts[0]);
                try {
                    yield update_repo_file ("focal", "focal", file);
                } catch (Error e) {
                    critical ("Failed to update source file %s: %s", file.get_path (), e.message);
                    throw new IOError.FAILED (e.message);
                }
            }


            yield task.refresh_cache_async (false, null, () => {});
            var upgradable_packes_result = yield task.get_updates_async (0, null, () => {});
            string[] package_ids = {};
            foreach (var package in upgradable_packes_result.get_package_array ()) {
                package_ids += package.package_id;
            }

            yield task.update_packages_async (package_ids, null, (progress, type) => {
                button.label = "%i %".printf (progress.percentage);
            });

            Pk.offline_trigger (REBOOT, null);
            button.label = "Trigger set, we are finished!";
        } catch (Error e) {
            warning (e.message);
        }
    }

    private async void update_repo_file (string from, string to, File file) throws Error {
        if (!file.query_exists ()) {
            return;
        }

        uint8[] old_contents = {};
        yield file.load_contents_async (null, out old_contents, null);

        var new_contents = ((string)old_contents).replace (from, to);
        yield file.replace_contents_async (new_contents.data, null, true, NONE, null, null);
    }
}
