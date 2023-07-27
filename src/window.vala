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
    public MainWindow (Application app) {
        application = app;
    }

    construct {
        var button = new Gtk.Button.with_label ("start update");
        child = button;
        default_width = 500;
        default_height = 500;

        button.clicked.connect (start_update);
    }

    private void start_update () {
        var client = new Pk.Client ();
        try {
            var results = client.get_repo_list (0, null, () => {});

            var updated_files = new GenericSet<string> (str_hash, str_equal);
            foreach (var repo in results.get_repo_detail_array ()) {
                var parts = repo.repo_id.split (":", 2);
                if (parts[0] in updated_files) {
                    continue;
                }

                updated_files.add (parts[0]);

                var file = File.new_for_path (parts[0]);
                update_repo_file ("jammy", "devel", file);
            }
        } catch (Error e) {
            warning (e.message);
            return;
        }
    }

    private void update_repo_file (string replace, string with, File file) {
        if (!file.query_exists ()) {
            return;
        }

        uint8[] old_contents = {};
        try {
            print ("starting file 1");
            file.load_contents (null, out old_contents, null);
            uint8[] new_contents = {};
            new_contents = (uint8[])((string)old_contents).replace (replace, with);
            file.replace_contents (new_contents, null, true, NONE, null, null);
            print ("Finished");
        } catch (Error e) {
            warning (e.message);
            return;
        }
    }
}
