# Family Veterinary Clinic Website

Website for Family Veterinary Clinic, 1413 Defense Hwy #100, Gambrills, MD (serving Crofton and Gambrills). It is a [Next.js](https://nextjs.org) app (React, Tailwind CSS, GSAP and Lenis smooth scrolling) that is **exported as a static site**: `npm run build` writes plain HTML, CSS and JavaScript into a `dist/` folder, so no Node.js server is needed to run it.

The site has a home page plus Privacy, Policies and Accessibility pages and a Resources section of articles (`/resources/<article>`), all generated at build time.

## Quick start

```bash
npm ci               # install dependencies (first time, or after package.json changes)
npm run build        # creates ./dist
```

**Point your domain's web server root at the `dist/` folder**, for example `/var/www/family-vet-clinic/dist`. The full Lightsail steps are below.

## Project structure

```
src/app/             Pages (home, privacy, policies, accessibility, resources), layout and global styles
src/components/      Sections and UI components
src/content/         Clinic details and links (site.ts), team, and the resource articles (JSON)
public/              Images and the client documents (PDFs), copied into dist/
next.config.ts       Static export settings (output: "export", distDir: "dist")
deploy/              fix-nginx.sh, see the Nginx section below
dist/                Build output. Point your domain here. Not committed to git.
```

## Run locally

Requires Node.js 20.9 or newer.

```bash
npm ci
npm run dev       # development server at http://localhost:3000
npm run build     # creates ./dist
npm start         # serves ./dist at http://localhost:3000
```

## Deploy to AWS Lightsail

These steps start **after you have cloned this repo on the Lightsail server** (as the `ubuntu` user, into `/var/www/family-vet-clinic`). Node.js and Nginx are set up for you by `sudo cpanel sites new`, so there is nothing to install by hand.

### 1. Build the site

```bash
cd /var/www/family-vet-clinic
npm ci
npm run build
```

The build downloads the site's Google fonts, so the server needs internet access while it runs. If this fails with `EACCES: permission denied`, see "If `npm run build` says permission denied" below.

This creates `/var/www/family-vet-clinic/dist`, the folder your domain will point at.

### 2. Create the site with `cpanel sites new`

```bash
sudo cpanel sites new
```

Answer the prompts like this (use your real domain):

| Prompt | Answer |
|--------|--------|
| Select application type | `4` (Static / React SPA) |
| Enter domain name | `example.com` |
| Enter site folder directory | `/var/www/family-vet-clinic/dist` |
| Apply secure ownership and permissions now? | `n` (so `ubuntu` can keep rebuilding). If you answer `y`, run `sudo chown -R ubuntu:ubuntu /var/www/family-vet-clinic` afterwards. |

The command writes the Nginx config for the domain (root set to the `dist` folder) and reloads Nginx.

### 3. Let Nginx serve the site's JavaScript and subpages (required for this site)

The `cpanel sites new` template has two problems for this site. It only allows `.js` files under `/assets/` or `/static/` (Next.js keeps its JavaScript in `/_next/static/`), and it answers every URL that is not a file with the home page, so `/privacy` and `/resources/...` would show the home page. **Without this step the page loads but has no animations, and the subpages are wrong.** Run once per domain:

```bash
cd /var/www/family-vet-clinic
sudo bash deploy/fix-nginx.sh example.com
```

See "If the site loads but animations or pages are missing" below for details.

### 4. Open the firewall in Lightsail

In the Lightsail console, open your instance, then **Networking**, then **IPv4 Firewall**. Make sure these rules exist: **HTTP (TCP 80)** and **HTTPS (TCP 443)**. Add the same rules under the IPv6 firewall if you use IPv6.

### 5. Point your domain at the server

1. In Lightsail, open **Networking**, then **Create static IP**, and attach it to the instance. Without this, the IP changes whenever the instance restarts.
2. At your domain registrar (or in the Lightsail DNS zone), create these records pointing to the static IP:

   | Type | Name | Value |
   |------|------|-------|
   | A | `@` | your static IP |
   | A | `www` | your static IP |

3. Wait for DNS to propagate (usually a few minutes, sometimes up to an hour). Check with `dig +short example.com`.

### 6. Check HTTPS

`cpanel sites new` sets up the HTTPS certificate for the domain. Once DNS points at the server, open `https://example.com`. If the browser shows no padlock or a certificate warning, get a certificate with Certbot:

```bash
sudo certbot --nginx -d example.com -d www.example.com
```

## Updating the site

After you push changes to GitHub, run this on the server:

```bash
cd /var/www/family-vet-clinic
git pull
npm ci
npm run build
```

Nginx serves the files straight from `dist`, so there is nothing to restart. Run these from the repo folder, not from inside `dist/`.

## If `npm run build` says "permission denied" (EACCES)

```
Error: EACCES: permission denied, mkdir '/var/www/family-vet-clinic/dist'
```

The build has to create a fresh `dist/` folder inside the repo folder, so the user running it (`ubuntu`) must own that folder. It does not when the repo was cloned with `sudo`, or when the `cpanel sites new` tool's "Apply secure ownership and permissions now?" prompt was answered `y` (that hands the folder to another user). Nginx does not need ownership, only read access, so giving the folder to `ubuntu` is safe:

```bash
ls -ld /var/www/family-vet-clinic /var/www/family-vet-clinic/dist      # shows who owns the folder (should say ubuntu)
sudo chown -R ubuntu:ubuntu /var/www/family-vet-clinic
cd /var/www/family-vet-clinic
npm ci
npm run build
```

The fix is per folder, so run it once for every site on the server. To fix several at once (change the names to match your folders; it is safe to run again on sites that are already fixed):

```bash
for s in family-vet-clinic dl-animal stjohn-vet animalhealth-center proactive-therapy bestfit-tailor kidderstreet-drycleaners deluxe-drycleaners littlebears-childcare; do
  [ -d /var/www/$s ] && sudo chown -R ubuntu:ubuntu /var/www/$s && echo "fixed $s"
done
```

If the error comes back later, something changed the ownership again (usually answering `y` to the `cpanel sites new` secure-ownership prompt, or running `git pull` or the build with `sudo`). Run the `chown` again, and check `ls -ld /var/www/family-vet-clinic` straight afterwards to see who owns it.

Tips:

- Clone as `ubuntu` (no `sudo`). If `/var/www` is not writable, create the folder once with `sudo mkdir /var/www/family-vet-clinic && sudo chown ubuntu:ubuntu /var/www/family-vet-clinic` and then clone into it.
- If `cpanel sites new` offers to apply secure ownership and permissions, answer `n`, or run the `chown` above straight after it finishes.
- Run `npm run build` from the repo folder, not from inside `dist/`. The build replaces `dist/`, which leaves a shell that is sitting inside it pointing at a deleted folder.

## If the site loads but animations or pages are missing (`cpanel sites new`)

Sites created with the server's `cpanel sites new` tool (Static / React SPA) get an Nginx config that only allows `.js` files under `/assets/` or `/static/`, and returns **404 for every other file extension**. This site's JavaScript lives in `/_next/static/`, so the template blocks it: the page shows only the plain HTML, with no animations, no menu and hidden sections. The template also serves the home page for any URL that is not a file, so `/privacy`, `/policies`, `/accessibility` and `/resources/...` would all show the home page. Fix both once per site on the server from the repo folder (replace the domain with yours):

```bash
cd /var/www/family-vet-clinic
sudo bash deploy/fix-nginx.sh example.com
```

The script backs up the Nginx config (to `/root/example.com.nginx.bak`), adds rules that allow `.js`, `.mjs`, `.html`, `.txt`, `.xml`, `.json`, `.pdf`, `.xlsx`, `.docx` and a few media files, makes `/privacy` serve `privacy.html` (and likewise for the other pages), tests the config, and reloads Nginx. If the test fails it puts the backup back. Running it twice is harmless.

Afterwards hard-refresh the site (Ctrl+Shift+R), and if the domain is behind Cloudflare, purge its cache (Caching, then Purge Everything). If you run `cpanel sites new` again for the same domain, it rewrites the config, so run the script again.

To check it worked, open the site with the browser's developer tools (F12) and look at the Console: there should be no red 404 errors for `/_next/static/...` files. Then open `https://example.com/privacy` and `https://example.com/resources/canine-influenza-aka-dog-flu`: each should show its own page, not the home page.

## Troubleshooting

- **`npm run build` fails with `EACCES: permission denied`:** the repo folder is not owned by `ubuntu`. See "If `npm run build` says permission denied" above and run `sudo chown -R ubuntu:ubuntu` on the repo folder.
- **Page loads but animations do not run, `/_next/static/...` files return 404, or `/privacy` shows the home page:** run `deploy/fix-nginx.sh` (step 3).
- **`npm run build` prints `Killed`:** the server ran out of memory. Add swap (for example `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`) and run the build again.
- **403 Forbidden:** Nginx cannot read the files. Run `sudo chmod -R o+rX /var/www/family-vet-clinic/dist`, and make sure the folders above it are readable (`ls -ld /var/www /var/www/family-vet-clinic`).
- **Default Nginx welcome page shows:** the domain has no site yet. Run `sudo cpanel sites new` for it (step 2).
- **Site not loading on the domain:** check the DNS records, the Lightsail firewall ports (80 and 443), and `sudo nginx -t`.
- **Changes not showing:** run `npm run build` again and hard-refresh the browser (Ctrl+Shift+R). Static files are cached for 30 days.
- **Logs:** `sudo tail -f /var/log/nginx/error.log`

## Notes

- **Static export:** the site is exported with `output: "export"` and `distDir: "dist"` in `next.config.ts`, and images use `unoptimized: true` because Next.js image optimization needs a server. Server features (API routes, server actions, middleware, `cookies()` and `headers()`) cannot be used with this setup. The `cacheComponents` and `partialPrefetching` options were removed from `next.config.ts` because static export does not support them.
- **Adding resource articles:** edit `src/content/articles.json` or `resource-pages.json`, then rebuild. Each slug becomes its own page at `/resources/<slug>`.
- **Next.js version:** `next` is pinned to 16.4.3. Versions 16.0.0 to 16.4.0 have critical security advisories, and `next build` stops with an error on them.
- **Contact form:** it has no backend. Submitting it opens the visitor's email app with a prefilled message to the clinic (see `src/components/sections/Contact.tsx`). To receive messages directly, connect a form service (for example Formspree) and change `onSubmit`.
- **External links:** appointments, the online pharmacy and several forms link to outside services or to pages on the clinic's previous website (`links` in `src/content/site.ts`). Update them if that site goes away.
- **Dates:** the footer year updates automatically.
