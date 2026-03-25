const fs = require("fs");
const path = require("path");

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function copyFile(src, dest) {
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
  console.log(`Copied: ${src} -> ${dest}`);
}

function main() {
  const projectRoot = path.join(__dirname, "..", "..");
  const srcRoot = path.join(projectRoot, "assets");
  const destRoot = path.join(projectRoot, "functions", "assets");

  const files = [
    {
      src: path.join(srcRoot, "poi", "solitaire_entrances.json"),
      dest: path.join(destRoot, "poi", "solitaire_entrances.json"),
    },
    {
      src: path.join(srcRoot, "connectors", "connectors_merged_local.json"),
      dest: path.join(destRoot, "connectors", "connectors_merged_local.json"),
    },
    {
      src: path.join(srcRoot, "nav_cor", "navmesh_GF.json"),
      dest: path.join(destRoot, "navmesh", "navmesh_GF.json"),
    },
    {
      src: path.join(srcRoot, "nav_cor", "navmesh_F1.json"),
      dest: path.join(destRoot, "navmesh", "navmesh_F1.json"),
    },
  ];

  for (const f of files) {
    if (!fs.existsSync(f.src)) {
      throw new Error(`Missing asset file: ${f.src}`);
    }
    copyFile(f.src, f.dest);
  }
}

main();
