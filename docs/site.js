// Floppeek's site: the download button, the release notes and the copy button.
//
// Everything about releases comes from GitHub's Releases API. The Download button
// points at a file the API lists (the .dmg of the latest release), never at a URL
// built from a version number; until the API answers, or if it does not, it points
// at the latest release's page, which always works. The notes arrive as HTML that
// GitHub renders from the release's markdown (the html+json media type).
(() => {
    "use strict";
    const REPO = "gfazioli/floppeek";

    document.querySelectorAll("[data-year]").forEach((el) => { el.textContent = String(new Date().getFullYear()); });

    // The greetings line scrolls only for visitors who have not asked for less motion:
    // doubled, so translating the track by half of its width loops seamlessly.
    const scroller = document.querySelector(".scroller");
    if (scroller && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
        const track = scroller.querySelector(".scroller-track");
        track.append(track.firstElementChild.cloneNode(true));
        scroller.dataset.loop = "";
    }

    // Served hidden: shown only where the clipboard can be written.
    const copy = document.getElementById("brew-copy");
    if (copy && navigator.clipboard) {
        copy.hidden = false;
        copy.addEventListener("click", async () => {
            try {
                await navigator.clipboard.writeText(document.getElementById("brew-command").textContent.trim());
                copy.textContent = "Copied";
                setTimeout(() => { copy.textContent = "Copy"; }, 1600);
            } catch { /* the command stays on screen to select by hand */ }
        });
    }

    // Only the home page has the download and the notes; the legal pages stop here.
    const list = document.getElementById("release-list");
    const download = document.getElementById("download");
    if (!list || !download) return;

    const megabytes = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;
    const day = (iso) => new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });

    fetch(`https://api.github.com/repos/${REPO}/releases?per_page=10`, {
        headers: { Accept: "application/vnd.github.html+json" },
    })
        .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
        .then((releases) => {
            const published = releases.filter((r) => !r.draft && !r.prerelease);
            if (!published.length) return;
            const latest = published[0];
            const dmg = (latest.assets || []).find((a) => a.name.endsWith(".dmg"));
            if (dmg) {
                download.href = dmg.browser_download_url;
                document.getElementById("download-label").textContent = `Download ${latest.tag_name.replace(/^v/, "")}`;
                const meta = document.getElementById("release-meta");
                if (meta) meta.textContent = `${megabytes(dmg.size)} DMG · ${day(latest.published_at)} · macOS 15 or later · Apple silicon and Intel`;
            }
            // The five latest above the page's own link to every version.
            list.prepend(...published.slice(0, 5).map((r) => {
                const article = document.createElement("article");
                article.className = "release";
                const title = document.createElement("h3");
                const link = document.createElement("a");
                link.href = r.html_url;
                link.textContent = r.name || r.tag_name;
                title.append(link);
                const date = document.createElement("time");
                date.dateTime = r.published_at;
                date.textContent = day(r.published_at);
                const body = document.createElement("div");
                body.className = "body";
                // GitHub's own rendering of the release's markdown, from this repository.
                body.innerHTML = r.body_html || "";
                article.append(title, date, body);
                return article;
            }));
        })
        .catch(() => { /* the static link to GitHub Releases stays */ });
})();
