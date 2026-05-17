async function loadPackages() {
  try {
    const response = await fetch("./packages.json");

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    return await response.json();
  } catch (err) {
    console.error("Failed to load packages:", err);

    const empty = document.getElementById("empty-state");

    empty.style.display = "block";

    empty.textContent = "Failed to load packages.json";

    return [];
  }
}

function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function normalizeLicense(license) {
  if (!license) {
    return "unknown";
  }

  if (typeof license === "string") {
    return license;
  }

  if (Array.isArray(license)) {
    return license.map(normalizeLicense).join(", ");
  }

  return (
    license.shortName ||
    license.spdxId ||
    license.fullName ||
    "unknown"
  );
}



function renderTable(packages) {
  const tbody = document.getElementById("packages-body");

  tbody.innerHTML = packages
    .map(
      (pkg) => `
        <tr>
          <td>
            <code>${escapeHtml(pkg.name)}</code>
          </td>

          <td class="version">${escapeHtml(pkg.version || "unknown")}</td>

          <td>
            <span class="license-badge">${escapeHtml(normalizeLicense(pkg.license))}</span>
          </td>

          <td class="description">${escapeHtml(pkg.description || "")}</td>

          <td>
            ${
              pkg.homepage
                ? `<a href="${escapeHtml(pkg.homepage)}" target="_blank" class="homepage-link">Homepage</a>`
                : ""
            }
          </td>
        </tr>
      `,
    )
    .join("");

  document.getElementById("package-count").textContent = packages.length;

  document.getElementById("empty-state").style.display =
    packages.length === 0 ? "block" : "none";
}

async function main() {
  const packages = await loadPackages();

  let filteredPackages = [...packages];

  let sortState = {
    key: "name",
    direction: 1,
  };

  function sortPackages(key, direction) {
    sortState = {
      key,
      direction,
    };

    document.querySelectorAll("th[data-sort]").forEach((th) => {
      th.classList.remove("sorted");
      const indicator = th.querySelector(".sort-indicator");
      if (indicator) {
        indicator.textContent = "↕";
      }
    });

    const activeTh = document.querySelector(`th[data-sort="${key}"]`);
    if (activeTh) {
      activeTh.classList.add("sorted");
      const indicator = activeTh.querySelector(".sort-indicator");
      if (indicator) {
        indicator.textContent = direction === 1 ? "↑" : "↓";
      }
    }

    filteredPackages.sort((a, b) => {
      const av = String(a[key] || "").toLowerCase();

      const bv = String(b[key] || "").toLowerCase();

      return av.localeCompare(bv) * direction;
    });

    renderTable(filteredPackages);
  }

  function filterPackages(query) {
    const q = query.toLowerCase().trim();

    filteredPackages = packages.filter((pkg) => {
      return [pkg.name, pkg.version, pkg.description]
        .join(" ")
        .toLowerCase()
        .includes(q);
    });

    sortPackages(sortState.key, sortState.direction);
  }

  // initial render
  sortPackages("name", 1);

  const searchInput = document.getElementById("search-input");

  searchInput.addEventListener("input", (e) => {
    filterPackages(e.target.value);
  });

  document.querySelectorAll("th[data-sort]").forEach((th) => {
    th.addEventListener("click", () => {
      const key = th.dataset.sort;

      let direction = 1;

      if (sortState.key === key) {
        direction = sortState.direction * -1;
      }

      sortPackages(key, direction);
    });
  });
}

main();
