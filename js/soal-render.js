/* ============================================================
 * soal-render.js — Renderer konten soal
 * ------------------------------------------------------------
 * Mendukung konten "blocks":
 *   { type:"text",  value:"..." }
 *   { type:"latex", value:"$...$ atau LaTeX tanpa dolar" }
 *   { type:"image", value:"<url> atau <dataURI>" }
 *
 * Renderer KaTeX aman (throwOnError=false) dengan fallback teks.
 * Dipakai di: ujian siswa, bank soal guru, editor preview.
 * ============================================================ */
(function (global) {
  "use strict";

  function renderLatex(latex, display) {
    var el = document.createElement("span");
    el.className = "math-inline";
    try {
      var src = String(latex).trim();
      if (/^\$\$/.test(src) && /\$\$$/.test(src)) src = src.replace(/^\$\$/, "").replace(/\$\$$/, "");
      else if (/^\$/.test(src) && /\$$/.test(src)) src = src.replace(/^\$/, "").replace(/\$$/, "");
      if (typeof window.katex !== "undefined") {
        window.katex.render(src, el, { throwOnError: false, displayMode: !!display });
      } else {
        el.textContent = src;
        el.classList.add("math-fallback");
      }
    } catch (e) {
      el.textContent = latex;
      el.classList.add("math-error");
      el.title = "LaTeX bermasalah: " + latex;
    }
    return el;
  }

  function renderText(value) {
    var el = document.createElement("span");
    var tokens = String(value).split(/(\$[^$]+\$)/g);
    tokens.forEach(function (tok) {
      if (tok && /^\$[^$]+\$$/.test(tok)) {
        el.appendChild(renderLatex(tok, false));
      } else {
        el.appendChild(document.createTextNode(tok));
      }
    });
    return el;
  }

  function renderImage(value) {
    var el = document.createElement("img");
    el.className = "soal-img";
    el.alt = "Gambar soal";
    el.style.maxWidth = "100%";
    el.style.maxHeight = "260px";
    el.style.display = "block";
    el.style.margin = "6px 0";
    el.style.borderRadius = "8px";
    el.src = value;
    el.onerror = function () {
      el.style.display = "none";
      var warn = document.createElement("span");
      warn.className = "badge badge-warn";
      warn.textContent = "⚠ gambar tidak dapat dimuat";
      el.parentNode && el.parentNode.appendChild(warn);
    };
    return el;
  }

  function renderBlock(block) {
    switch (block.type) {
      case "latex": return renderLatex(block.value, false);
      case "image": return renderImage(block.value);
      case "text":
      default: return renderText(block.value);
    }
  }

  /** Render array blocks -> elemen span kontainer */
  global.RenderSoal = {
    blocks: function (blocks) {
      var wrap = document.createElement("span");
      (blocks || []).forEach(function (b) {
        wrap.appendChild(renderBlock(b));
        wrap.appendChild(document.createTextNode(" "));
      });
      return wrap;
    },
    /** Sumber teks mentah untuk debugging / preview */
    teksMentah: function (blocks) {
      return (blocks || []).map(function (b) {
        return b.type === "image" ? "[GAMBAR]" : b.value;
      }).join(" ");
    }
  };
})(window);
