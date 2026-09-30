import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const source = resolve("dist/web");
const destination = resolve("editor/public/game");
const tileSource = resolve("assets/isometric tileset/separated images");
const tileDestination = resolve("editor/public/tiles/isometric");

await mkdir(destination, { recursive: true });
// Copy the compiled game into the preview asset directory before patching its entry page.
await cp(source, destination, { recursive: true, force: true });
await mkdir(tileDestination, { recursive: true });
await cp(tileSource, tileDestination, { recursive: true, force: true });

const indexPath = resolve(destination, "index.html");
let html = await readFile(indexPath, "utf8");
const injection = `
    <script>
      // The editor stores a validated candidate before reloading this frame.
      // Register after game.js so this preRun callback overwrites packaged data.
      // Accept preview-content messages only from the same origin and acknowledge storage.
      window.addEventListener("message", function (event) {
        if (event.origin !== window.location.origin || !event.data || event.data.type !== "cardgame.content.apply") return;
        try {
          localStorage.setItem("cardgame.preview.content", JSON.stringify(event.data.content));
          parent.postMessage({ type: "cardgame.content.stored", requestId: event.data.requestId }, event.origin);
        } catch (error) {
          parent.postMessage({ type: "cardgame.content.result", requestId: event.data.requestId, ok: false, errors: [String(error)] }, event.origin);
        }
      });
    </script>
`;
const preload = `
    <script>
      Module.preRun = Module.preRun || [];
      // Hold runtime startup while a saved draft replaces the packaged content file.
      Module.preRun.push(function () {
        var raw = localStorage.getItem("cardgame.preview.content");
        if (!raw) return;
        var dependency = "cardgame-editor-preview";
        Module.addRunDependency(dependency);

        // Install the draft after package downloads finish, then release the startup dependency.
        function installPreviewContent() {
          // game.js creates packaged files asynchronously. Wait until it has
          // completed so the editor's file is the final version Lua sees.
          if ((Module.finishedDataFileDownloads || 0) < (Module.expectedDataFileDownloads || 0)) {
            setTimeout(installPreviewContent, 0);
            return;
          }

          try {
            var parsed = JSON.parse(raw);
            // Remove an earlier file if present; a missing file is expected on first installation.
            try { Module.FS_unlink("/content/content.json"); } catch (_) {}
            Module.FS_createPath("/", "content", true, true);
            Module.FS_createDataFile(
              "/content",
              "content.json",
              new TextEncoder().encode(raw),
              true,
              true,
              true
            );
            parent.postMessage({
              type: "cardgame.content.result",
              ok: true,
              revision: parsed.contentRevision,
              featuredCardId: parsed.preview && parsed.preview.featuredCardId
            }, window.location.origin);
          } catch (error) {
            parent.postMessage({ type: "cardgame.content.result", requestId: null, ok: false, errors: [String(error)] }, window.location.origin);
          } finally {
            // Release startup on success or failure so an invalid draft cannot leave the loader waiting.
            Module.removeRunDependency(dependency);
          }
        }

        installPreviewContent();
      });
    </script>
`;
// Register the message bridge before game.js and the preRun hook after it.
html = html.replace('<script type="text/javascript" src="game.js"></script>', injection + '<script type="text/javascript" src="game.js"></script>' + preload);
await writeFile(indexPath, html, "utf8");
