import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const source = resolve("dist/web");
const destination = resolve("editor/public/game");

await mkdir(destination, { recursive: true });
await cp(source, destination, { recursive: true, force: true });

const indexPath = resolve(destination, "index.html");
let html = await readFile(indexPath, "utf8");
const injection = `
    <script>
      // The editor stores a validated candidate before reloading this frame.
      // Register after game.js so this preRun callback overwrites packaged data.
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
      Module.preRun.push(function () {
        var raw = localStorage.getItem("cardgame.preview.content");
        if (!raw) return;
        var dependency = "cardgame-editor-preview";
        Module.addRunDependency(dependency);

        function installPreviewContent() {
          // game.js creates packaged files asynchronously. Wait until it has
          // completed so the editor's file is the final version Lua sees.
          if ((Module.finishedDataFileDownloads || 0) < (Module.expectedDataFileDownloads || 0)) {
            setTimeout(installPreviewContent, 0);
            return;
          }

          try {
            var parsed = JSON.parse(raw);
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
            Module.removeRunDependency(dependency);
          }
        }

        installPreviewContent();
      });
    </script>
`;
html = html.replace('<script type="text/javascript" src="game.js"></script>', injection + '<script type="text/javascript" src="game.js"></script>' + preload);
await writeFile(indexPath, html, "utf8");
