public static int main (string[] args) {
    // Ensure GNOME env vars are set for proper theming
    Environment.set_variable ("GSK_RENDERER", "gl", false);

    var app = new LLMStudio.Application ();
    return app.run (args);
}
