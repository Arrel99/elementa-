# Ilustrasi Kartu Elementa

Taruh file gambar di folder ini. **Nama file harus sama dengan `id` kartu**
(lihat `data/cards/*.tres`). Format didukung: `.png` (disarankan, transparan),
`.webp`, `.jpg`, `.svg`.

Contoh: `H2O.png` akan dipakai oleh kartu `H2O`.

## Cara pakai

### Cara cepat (otomatis)
1. Taruh semua gambar di folder ini dengan nama sesuai daftar di bawah.
2. Buka Godot, tunggu sampai gambar terimpor (lihat tab FileSystem).
3. Buka `scripts/tools/assign_art.gd` di editor skrip, lalu **File > Run**
   (Ctrl+Shift+X). Skrip akan mengisi field `art` tiap kartu dan melaporkan
   kartu yang belum punya gambar.

### Cara manual (per kartu)
1. Klik dua kali `data/cards/H2O.tres` -> panel Inspector terbuka di kanan.
2. Tarik `H2O.png` dari FileSystem ke field **Art** di Inspector.
3. Ctrl+S. Ulangi untuk kartu lain.

## Ukuran yang disarankan
- Rasio kartu kira-kira **3:4**, mis. 384x512 px atau 600x800 px.
- PNG dengan latar transparan supaya menyatu dengan bingkai kartu.
- Usahakan semua kartu ukurannya sama agar baris tangan rapi.

## Daftar nama file (26 kartu)

Kartu dasar:
```
H.png  O.png  C.png  N.png  Na.png  Cl.png  Ca.png  Fe.png  Cu.png  Ne.png
```

Kartu spesial (senyawa):
```
H2O.png  CO2.png  NaCl.png  NH3.png  CH4.png  CaO.png  CuO.png  Fe2O3.png  HCl.png
```

Spell:
```
elektrolisis.png  katalis.png  spektrometer.png  bilas.png
korosi.png  elektrolisis_paksa.png  perisai_inert.png
```

Jika nama berbeda dari daftar ini, ganti `id` kartu di file `.tres`-nya — tapi
ingat: **id tidak boleh diubah setelah game dirilis** (log, tes, dan resep
merujuk ke id).
