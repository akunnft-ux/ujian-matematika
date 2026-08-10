/* ============================================================
 * docx-parser.js — Parser soal dari file .docx
 * ------------------------------------------------------------
 * Pipeline (semua client-side):
 *   .docx → JSZip unzip → word/document.xml
 *     ├─ w:t        → teks
 *     ├─ m:oMath    → OMML → MathML → LaTeX (omml2mathml + mathml-to-latex)
 *     ├─ a:blip     → gambar → data URI / upload Drive
 *     └─ w:br/w:tab → baris / spasi
 *   → pisah soal per nomor + opsi A..E + bagian "KUNCI JAWABAN"
 *
 * Keterangan: konversi OMML memakai library optional yang di-load
 * dari CDN. Bila library tidak tersedia, OMML ditandai placeholder
 * "persamaan perlu diperbaiki" (konsisten dgn keputusan fallback).
 * ============================================================ */
(function (global) {
  "use strict";

  /* Konversi OMML string → LaTeX, fallback aman. */
  function ommlToLatex(ommlXml) {
    try {
      if (window.omml2mathml && window.mathml2latex) {
        var mathml = window.omml2mathml(ommlXml);
        if (mathml) {
          var latex = window.mathml2latex(MathML2LaTeX.convert ? MathML2LaTeX.convert(mathml) : mathml);
          return latex || null;
        }
      }
      if (window.Plurimath) {
        // Plurimath: OMML -> LaTeX langsung (bila tersedia)
        return null; // (placeholder — di-handle jalur MathML di atas)
      }
    } catch (e) { /* fallthrough */ }
    return null;
  }

  function extractTextFromWt(node) {
    var out = "";
    node.querySelectorAll("w\\:t, t").forEach(function (t) {
      out += t.textContent;
    });
    return out;
  }

  /* ============ CORE: parse document.xml jadi blok ============ */
  function parseDocumentXML(xmlText) {
    var parser = new DOMParser();
    var doc = parser.parseFromString(xmlText, "application/xml");
    if (doc.querySelector("parsererror")) throw new Error("XML soal tidak valid.");

    var body = doc.getElementsByTagNameNS("*", "body")[0] ||
               doc.getElementsByTagName("w\\:body")[0] ||
               doc.documentElement;
    if (!body) throw new Error("Struktur document.xml tidak ditemukan.");

    var blocks = [];
    var paragraphs = body.querySelectorAll("w\\:p, p");
    if (!paragraphs.length) paragraphs = body.querySelectorAll("*[w\\:p], p, body > *");

    paragraphs.forEach(function (p) {
      var line = { teks: [], latex: [], images: [] };
      // text runs
      p.querySelectorAll("w\\:t, t").forEach(function (t) { line.teks.push(t.textContent); });
      // OMML math
      p.querySelectorAll("m\\:oMath, oMath").forEach(function (m) {
        var latex = ommlToLatex(new XMLSerializer().serializeToString(m));
        line.latex.push(latex || "[PERSAMAAN_PERLU_DIPERBAIKI]");
      });
      // images
      p.querySelectorAll("a\\:blip, blip").forEach(function (bl) {
        var rid = bl.getAttribute("r:embed") || bl.getAttribute("embed");
        if (rid) line.images.push(rid);
      });

      var text = line.teks.join("").trim();
      if (text || line.latex.length || line.images.length) {
        blocks.push({ kind: "line", text: text, latex: line.latex, images: line.images });
      }
    });
    return { doc: doc, blocks: blocks };
  }

  function extractImageRelations(doc) {
    // rels di word/_rels/document.xml.rels → rId → media file
    var rels = {};
    var relNodes = doc.querySelectorAll("Relationship");
    relNodes.forEach(function (r) {
      var id = r.getAttribute("Id");
      var target = r.getAttribute("Target") || "";
      var mode = r.getAttribute("TargetMode") || "";
      if (id && /image|media/i.test(target) && mode !== "External") {
        var name = target.replace(/^.*\/|\//g, "");
        rels[id] = "word/" + (target.indexOf("media/") >= 0 ? target : "media/" + name);
      }
    });
    return rels;
  }

  /* ============ SPLIT soal: "1." + opsi + KUNCI JAWABAN ============ */
  function splitQuestions(lines) {
    var soal = [];
    var current = null;
    var diKunci = false;
    var kunciLines = [];
    var kode = "";

    function startQuestion(nomor) {
      current = { nomor: nomor, blocks: [], opsi: [], line: null };
      soal.push(current);
    }

    lines.forEach(function (l) {
      var mKode = l.text.match(/^\s*KODE\s*SOAL\s*[:]\s*(.+)\s*$/i);
      if (mKode) { kode = mKode[1].trim(); return; }
      if (/^\s*KUNCI\s*JAWABAN\s*[:]*\s*$/i.test(l.text)) { diKunci = true; return; }
      if (diKunci) { if (l.text.trim()) kunciLines.push(l.text); return; }

      var mNomor = l.text.match(/^\s*(\d{1,3})[.)]\s*(.*)$/);
      var mOpsi = l.text.match(/^\s*([A-E])[.)]\s*(.*)$/);
      var mOpsiSmall = l.text.match(/^\s*([a-e])[.)]\s*(.*)$/);

      if (mNomor) {
        startQuestion(parseInt(mNomor[1], 10));
        current.line = mNomor[2];
        pushTextToCurrent(current, mNomor[2]);
        return;
      }
      if (mOpsi) {
        if (current) current.opsi.push(mOpsi[2]);
        else { // opsi tanpa soal — buat soal longgar
          startQuestion(soal.length + 1);
          current.opsi.push(mOpsi[2]);
        }
        return;
      }
      if (mOpsiSmall) {
        if (current) current.opsi.push(mOpsiSmall[2].toUpperCase());
        return;
      }
      if (current) pushTextToCurrent(current, l.text);
    });

    // terapkan kode soal ke semua soal dalam paket
    soal.forEach(function (s) { s.kode = kode; });

    // apply kunci ke soal
    kunciLines.forEach(function (kl) {
      var mk = kl.match(/(\d{1,3})\s*[.)]?\s*([A-Ea-e])/);
      if (mk) {
        var s = soal.find(function (x) { return x.nomor === parseInt(mk[1], 10); });
        if (s) s.kunci = mk[2].toUpperCase();
      }
    });

    return soal;
  }

  function pushTextToCurrent(current, text) {
    current.blocks.push({ type: "text", value: text });
  }

  /* ============ PUBLIC ============ */
  global.DocxParser = {
    /** @returns Promise<soal[]> struktur soal dari .docx */
    parse: function (file, onProgress) {
      return new Promise(function (resolve, reject) {
        if (typeof JSZip === "undefined") {
          reject(new Error("Library JSZip belum dimuat.")); return;
        }
        onProgress && onProgress("Membuka file .docx...");
        JSZip.loadAsync(file).then(function (zip) {
          onProgress && onProgress("Membaca konten dokumen...");
          return zip.file("word/document.xml").async("string").then(function (xml) {
            var parsed = parseDocumentXML(xml);
            // rels
            var rels = {};
            var relFile = zip.file("word/_rels/document.xml.rels");
            if (relFile) {
              return relFile.async("string").then(function (relsXml) {
                var rdoc = new DOMParser().parseFromString(relsXml, "application/xml");
                rels = extractImageRelations(rdoc);
                return resolve(assembleSoal(parsed, zip, rels, onProgress));
              });
            }
            return resolve(assembleSoal(parsed, zip, rels, onProgress));
          });
        }).catch(reject);
      });
    }
  };

  function assembleSoal(parsed, zip, rels, onProgress) {
    var lines = parsed.blocks.filter(function (b) {
      return b.text || b.latex.length || b.images.length;
    }).map(function (b) {
      var html = b.text;
      b.latex.forEach(function (l) {
        html += l.indexOf("[PERSAMAAN") === 0 ? " " + l + " " : " $latex=" + l + "$ ";
      });
      b.images.forEach(function (rid) {
        var path = rels[rid];
        html += " [GAMBAR:" + (path || rid) + "]";
      });
      return { text: html };
    });

    var soal = splitQuestions(lines);
    soal.forEach(function (s) {
      // kembalikan LaTeX placeholder → blok latex, dan gambar → blok image
      var finalBlocks = [];
      s.blocks.forEach(function (b) {
        var v = b.value;
        if (v && v.indexOf("$latex=") >= 0) {
          var parts = v.split(/(\$latex=[^\$]*\$)/g);
          parts.forEach(function (pp) {
            if (pp && pp.indexOf("$latex=") === 0) {
              var latext = pp.replace(/^\$latex=/, "").replace(/\$$/, "").trim();
              if (latext && latext.indexOf("[PERSAMAAN") === 0) {
                finalBlocks.push({ type: "text", value: "[⚠ persamaan perlu diperbaiki di sini]" });
              } else {
                finalBlocks.push({ type: "latex", value: latext });
              }
            } else if (pp) {
              finalBlocks.push({ type: "text", value: pp });
            }
          });
        } else {
          // gambar dalam text
          var gparts = v.split(/(\[GAMBAR:[^\]]+\])/g);
          gparts.forEach(function (pp) {
            var gm = pp.match(/\[GAMBAR:([^\]]+)\]/);
            if (gm) {
              finalBlocks.push({ type: "image", value: gm[1] }); // path mentah; guru bisa ganti
            } else if (pp) {
              finalBlocks.push({ type: "text", value: pp });
            }
          });
        }
      });
      s.blocks = finalBlocks.filter(function (b) { return String(b.value).trim() !== ""; });
      s.status = "draft";
    });
    return soal;
  }
})(window);
