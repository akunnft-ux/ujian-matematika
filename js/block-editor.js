/* ============================================================
 * block-editor.js — Block-based editor untuk isi soal
 * ------------------------------------------------------------
 * Isi soal = array blocks: {type:text|latex|image, value}
 * - Tambah block: Teks, Persamaan (LaTeX+preview), Gambar (upload)
 * - Tiap block: edit inline, hapus, pindah atas/bawah
 * - Preview KaTeX real-time
 * - getBlocks() menghasilkan JSON siap simpan
 *
 * Dipakai di: form tambah soal manual + modal edit bank soal.
 * ============================================================ */
(function (global) {
  "use strict";

  function createEl(tag, cls, html) {
    var el = document.createElement(tag);
    if (cls) el.className = cls;
    if (html !== undefined) el.innerHTML = html;
    return el;
  }

  function buildBlockEditor(container, initialBlocks, opts) {
    opts = opts || {};
    var blocks = (initialBlocks || []).map(function (b) { return { type: b.type, value: b.value }; });
    if (!blocks.length) blocks = [{ type: "text", value: "" }];

    var wrapper = createEl("div", "be-wrapper");
    var listEl = createEl("div", "be-list");
    wrapper.appendChild(listEl);
    container.appendChild(wrapper);

    function previewOf(block) {
      var p = document.createElement("span");
      if (block.type === "latex") {
        var tmp = document.createElement("span");
        try {
          var src = block.value;
          if (/^\$\$/.test(src) && /\$\$$/.test(src)) src = src.replace(/^\$\$/, "").replace(/\$\$$/, "");
          else if (/^\$/.test(src) && /\$$/.test(src)) src = src.replace(/^\$/, "").replace(/\$$/, "");
          window.katex.render(src, tmp, { throwOnError: false });
        } catch (e) { tmp.textContent = block.value; }
        p = tmp;
      } else if (block.type === "image") {
        var img = document.createElement("img");
        img.src = block.value;
        img.style.maxHeight = "80px";
        img.style.maxWidth = "120px";
        img.style.borderRadius = "6px";
        img.style.verticalAlign = "middle";
        p = img;
      } else {
        p.textContent = block.value;
      }
      return p;
    }

    function render() {
      listEl.innerHTML = "";
      blocks.forEach(function (block, i) {
        var row = createEl("div", "be-row");

        var badge = createEl("span", "be-badge be-badge-" + block.type,
          block.type === "text" ? "T" : block.type === "latex" ? "∑" : "🖼");
        row.appendChild(badge);

        var body = createEl("div", "be-body");

        var preview = createEl("div", "be-preview");
        preview.appendChild(previewOf(block));
        body.appendChild(preview);

        var input = createEl("textarea", "be-input");
        input.rows = 2;
        input.placeholder = block.type === "latex"
          ? "LaTeX: contoh  \\frac{a}{b}  (tanpa tanda $)"
          : block.type === "image"
            ? "URL gambar (atau gunakan tombol upload)"
            : "Tulis teks soal... (bisa $latex$ inline)";
        input.value = block.type === "image" ? block.value : block.value;
        input.dataset.i = i;
        input.addEventListener("input", function () {
          blocks[i].value = input.value;
          preview.innerHTML = "";
          preview.appendChild(previewOf(blocks[i]));
        });
        body.appendChild(input);

        if (block.type === "image") {
          var uploadBtn = createEl("button", "be-btn be-btn-small", "⬆ Upload gambar");
          var fileInput = document.createElement("input");
          fileInput.type = "file";
          fileInput.accept = "image/*";
          fileInput.style.display = "none";
          uploadBtn.addEventListener("click", function () { fileInput.click(); });
          fileInput.addEventListener("change", function () {
            var f = fileInput.files[0];
            if (!f) return;
            var rd = new FileReader();
            rd.onload = function () {
              blocks[i].value = rd.result; // data URI
              input.value = rd.result;
              preview.innerHTML = "";
              preview.appendChild(previewOf(blocks[i]));
            };
            rd.readAsDataURL(f);
          });
          body.appendChild(uploadBtn);
          body.appendChild(fileInput);
        }

        row.appendChild(body);

        var actions = createEl("div", "be-actions");
        var btnUp = createEl("button", "be-btn be-btn-small", "▲");
        btnUp.title = "Naik";
        btnUp.addEventListener("click", function () {
          if (i > 0) { var t = blocks[i - 1]; blocks[i - 1] = blocks[i]; blocks[i] = t; render(); }
        });
        var btnDown = createEl("button", "be-btn be-btn-small", "▼");
        btnDown.title = "Turun";
        btnDown.addEventListener("click", function () {
          if (i < blocks.length - 1) { var t = blocks[i + 1]; blocks[i + 1] = blocks[i]; blocks[i] = t; render(); }
        });
        var btnDel = createEl("button", "be-btn be-btn-small be-btn-del", "✕");
        btnDel.title = "Hapus block ini";
        btnDel.addEventListener("click", function () {
          blocks.splice(i, 1);
          if (!blocks.length) blocks = [{ type: "text", value: "" }];
          render();
        });
        actions.appendChild(btnUp);
        actions.appendChild(btnDown);
        actions.appendChild(btnDel);
        row.appendChild(actions);

        listEl.appendChild(row);
      });

      var addBar = createEl("div", "be-addbar");
      [["text", "+ Teks"], ["latex", "+ Persamaan"], ["image", "+ Gambar"]].forEach(function (def) {
        var b = createEl("button", "be-btn be-btn-add", def[1]);
        b.addEventListener("click", function () {
          blocks.push({ type: def[0], value: "" });
          render();
        });
        addBar.appendChild(b);
      });
      wrapper.appendChild(addBar);
    }

    render();

    return {
      getBlocks: function () {
        return blocks.filter(function (b) { return b.type !== "text" || String(b.value).trim() !== ""; })
          .map(function (b) { return { type: b.type, value: b.value }; });
      },
      isEmpty: function () {
        var s = blocks.filter(function (b) { return String(b.value).trim() !== ""; });
        return s.length === 0;
      }
    };
  }

  global.BlockEditor = { create: buildBlockEditor };
})(window);
