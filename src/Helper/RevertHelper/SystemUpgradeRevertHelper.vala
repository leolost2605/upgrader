public async static int main (string[] args) {
    var file_name = args[1];

    var file = File.new_for_path (file_name);
    var backup_file = File.new_for_path (file_name + "." + "save");

    if (!backup_file.query_exists ()) {
        printerr ("Couldn't find backup file!");
        return 1;
    }

    try {
        yield backup_file.copy_async (file, OVERWRITE);
        return 0;
    } catch (Error e) {
        printerr ("Failed to backup from file %s: %s", backup_file.get_path (), e.message);
        return 1;
    }
}
