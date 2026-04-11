# GitHub Pages

The browser visualizer under [`packet_transmission/`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission) is now set up to be deployable through GitHub Pages.

## What Was Added

- [`larpix-visualizer-pages.yml`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/.github/workflows/larpix-visualizer-pages.yml)

That workflow publishes the contents of:

- [`packet_transmission/`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission)

as a self-contained static site.

## Expected URL

Once this repository is pushed to GitHub and Pages is enabled, the visualizer URL should be:

```text
https://<github-user>.github.io/<repo-name>/
```

Because the workflow publishes `packet_transmission/` as the site root, the app should open directly at the Pages root rather than under a nested path.

## Remaining Manual Steps

1. Push this repository to GitHub.
2. In the GitHub repository settings, enable Pages with `GitHub Actions` as the source.
3. Wait for the `Deploy LArPix Visualizer to GitHub Pages` workflow to complete.
4. Open the published `github.io` URL.

## Notes

- The visualizer already uses relative asset paths, so it is compatible with Pages hosting.
- The default playback file remains:
  - [`live_bootstrap_3x5.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json)
- I cannot create the live public URL from this environment, but the workflow is now in place so GitHub can do that after push.
