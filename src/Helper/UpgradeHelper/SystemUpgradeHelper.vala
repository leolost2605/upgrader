public async static int main (string[] args) {
    string old_codename = args[1];
    string new_codename = args[2];
    GLib.File file = GLib.File.new_for_path (args[3]);

    if (!file.query_exists ()) {
        return 1;
    }

    var backup_file = GLib.File.new_for_path (file.get_path () + "." + "save");
    try {
        if (!yield file.copy_async (backup_file, OVERWRITE)) { //TODO i guess we don't need the if here because if it return false it already fails?
            printerr ("Failed to back up repo file %s.", file.get_path());
            return 1;
        }
    } catch (Error e) {
        printerr ("Failed to back up repo file %s: %s", file.get_path(), e.message);
        return 1;
    }

    try {
        uint8[] old_contents = {};
        yield file.load_contents_async (null, out old_contents, null);

        var new_contents = ((string)old_contents).replace (old_codename, new_codename);
        yield file.replace_contents_async (new_contents.data, null, true, NONE, null, null);
        return 0;
    } catch (Error e) {
        printerr ("Failed to update repo file %s: %s", file.get_path(), e.message);
        return 1;
    }
}
