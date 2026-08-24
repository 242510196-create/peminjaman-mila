-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Waktu pembuatan: 24 Agu 2026 pada 08.09
-- Versi server: 10.4.32-MariaDB
-- Versi PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `peminjaman_alat`
--

DELIMITER $$
--
-- Prosedur
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_setujui_peminjaman` (IN `p_peminjaman_id` BIGINT UNSIGNED, IN `p_petugas_id` BIGINT UNSIGNED)   BEGIN
                DECLARE v_selesai   INT DEFAULT 0;
                DECLARE v_alat_id   BIGINT UNSIGNED;
                DECLARE v_jumlah    INT;
                DECLARE v_tersedia  INT;
                DECLARE v_nama_alat VARCHAR(150);
                DECLARE v_status    VARCHAR(30);
                DECLARE v_pesan     VARCHAR(255);
                DECLARE v_kode      VARCHAR(20);

                DECLARE kursor_detail CURSOR FOR
                    SELECT alat_id, jumlah
                    FROM detail_peminjaman
                    WHERE peminjaman_id = p_peminjaman_id;

                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_selesai = 1;

                -- Pemeriksaan 1: status harus masih diajukan.
                SELECT status, kode_pinjam INTO v_status, v_kode
                FROM peminjaman WHERE id = p_peminjaman_id;

                IF v_status IS NULL THEN
                    SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Data peminjaman tidak ditemukan';
                END IF;

                IF v_status <> 'diajukan' THEN
                    SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Peminjaman ini sudah pernah diproses';
                END IF;

                -- Pemeriksaan 2: seluruh baris alat harus mencukupi stoknya.
                OPEN kursor_detail;

                periksa_stok: LOOP
                    FETCH kursor_detail INTO v_alat_id, v_jumlah;

                    IF v_selesai = 1 THEN
                        LEAVE periksa_stok;
                    END IF;

                    SELECT stok_tersedia, nama
                    INTO v_tersedia, v_nama_alat
                    FROM alat WHERE id = v_alat_id FOR UPDATE;

                    IF v_tersedia < v_jumlah THEN
                        SET v_pesan = CONCAT(
                            'Stok tidak mencukupi untuk ', v_nama_alat,
                            ' (diminta ', v_jumlah, ', tersedia ', v_tersedia, ')'
                        );

                        CLOSE kursor_detail;

                        SIGNAL SQLSTATE '45000'
                        SET MESSAGE_TEXT = v_pesan;
                    END IF;
                END LOOP;

                CLOSE kursor_detail;

                -- Semua baris lolos: kurangi stok sekaligus.
                UPDATE alat a
                JOIN detail_peminjaman d ON d.alat_id = a.id
                SET a.stok_tersedia = a.stok_tersedia - d.jumlah
                WHERE d.peminjaman_id = p_peminjaman_id;

                UPDATE peminjaman
                SET status     = 'dipinjam',
                    petugas_id = p_petugas_id,
                    updated_at = NOW()
                WHERE id = p_peminjaman_id;

                INSERT INTO log_aktivitas
                (user_id, aksi, tabel_tujuan, deskripsi, created_at)
                VALUES
                (p_petugas_id, 'setujui', 'peminjaman',
                 CONCAT('Menyetujui peminjaman ', v_kode), NOW());
            END$$

--
-- Fungsi
--
CREATE DEFINER=`root`@`localhost` FUNCTION `fn_hitung_denda` (`p_tgl_harus_kembali` DATE, `p_tgl_kembali` DATE, `p_jumlah_unit` INT, `p_tarif_harian` INT) RETURNS DECIMAL(12,2) DETERMINISTIC BEGIN
        DECLARE v_hari_terlambat INT;

        SET v_hari_terlambat = DATEDIFF(
            p_tgl_kembali,
            p_tgl_harus_kembali
        );

        IF v_hari_terlambat < 0 THEN
            SET v_hari_terlambat = 0;
        END IF;

        RETURN v_hari_terlambat * p_jumlah_unit * p_tarif_harian;
    END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Struktur dari tabel `alat`
--

CREATE TABLE `alat` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `kategori_id` bigint(20) UNSIGNED NOT NULL,
  `kode_alat` varchar(30) NOT NULL,
  `nama` varchar(150) NOT NULL,
  `deskripsi` text DEFAULT NULL,
  `stok` int(11) NOT NULL DEFAULT 0,
  `stok_tersedia` int(11) NOT NULL DEFAULT 0,
  `kondisi` enum('baik','rusak_ringan','rusak_berat') NOT NULL DEFAULT 'baik',
  `foto` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ;

--
-- Dumping data untuk tabel `alat`
--

INSERT INTO `alat` (`id`, `kategori_id`, `kode_alat`, `nama`, `deskripsi`, `stok`, `stok_tersedia`, `kondisi`, `foto`, `created_at`, `updated_at`) VALUES
(1, 1, 'PKT-001', 'Obeng Plus Set', NULL, 10, 10, 'baik', NULL, '2026-08-23 21:22:45', '2026-08-23 21:22:45'),
(2, 1, 'PKT-002', 'Tang Kombinasi', NULL, 8, 8, 'baik', NULL, '2026-08-23 21:22:45', '2026-08-23 21:22:45'),
(3, 1, 'PKT-003', 'Kunci Pas Set', NULL, 6, 6, 'baik', NULL, '2026-08-23 21:22:45', '2026-08-23 21:22:45'),
(4, 2, 'AUK-001', 'Multimeter Digital', NULL, 12, 12, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(5, 2, 'AUK-002', 'Jangka Sorong', NULL, 9, 8, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(6, 2, 'AUK-003', 'Mistar Baja 30 cm', NULL, 15, 15, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(7, 3, 'JAR-001', 'Tang Crimping RJ45', NULL, 10, 10, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(8, 3, 'JAR-002', 'LAN Tester', NULL, 5, 5, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(9, 3, 'JAR-003', 'Switch 8 Port', NULL, 4, 4, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(10, 4, 'AVI-001', 'Proyektor Portable', NULL, 3, 3, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(11, 4, 'AVI-002', 'Tripod Kamera', NULL, 6, 6, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46'),
(12, 4, 'AVI-003', 'Kamera Mirrorless', NULL, 2, 2, 'baik', NULL, '2026-08-23 21:22:46', '2026-08-23 21:22:46');

-- --------------------------------------------------------

--
-- Struktur dari tabel `cache`
--

CREATE TABLE `cache` (
  `key` varchar(255) NOT NULL,
  `value` mediumtext NOT NULL,
  `expiration` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `cache`
--

INSERT INTO `cache` (`key`, `value`, `expiration`) VALUES
('peminjaman-alat-cache-spatie.permission.cache', 'a:3:{s:5:\"alias\";a:4:{s:1:\"a\";s:2:\"id\";s:1:\"b\";s:4:\"name\";s:1:\"c\";s:10:\"guard_name\";s:1:\"r\";s:5:\"roles\";}s:11:\"permissions\";a:13:{i:0;a:4:{s:1:\"a\";i:1;s:1:\"b\";s:11:\"user.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:1;a:4:{s:1:\"a\";i:2;s:1:\"b\";s:11:\"alat.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:2;a:4:{s:1:\"a\";i:3;s:1:\"b\";s:15:\"kategori.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:3;a:4:{s:1:\"a\";i:4;s:1:\"b\";s:17:\"peminjaman.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:4;a:4:{s:1:\"a\";i:5;s:1:\"b\";s:19:\"pengembalian.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:5;a:4:{s:1:\"a\";i:6;s:1:\"b\";s:9:\"log.lihat\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:6;a:4:{s:1:\"a\";i:7;s:1:\"b\";s:17:\"pengaturan.kelola\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:1;}}i:7;a:4:{s:1:\"a\";i:8;s:1:\"b\";s:18:\"peminjaman.setujui\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:2;}}i:8;a:4:{s:1:\"a\";i:9;s:1:\"b\";s:19:\"pengembalian.pantau\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:2;}}i:9;a:4:{s:1:\"a\";i:10;s:1:\"b\";s:13:\"laporan.cetak\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:2;}}i:10;a:4:{s:1:\"a\";i:11;s:1:\"b\";s:10:\"alat.lihat\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:3;}}i:11;a:4:{s:1:\"a\";i:12;s:1:\"b\";s:17:\"peminjaman.ajukan\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:3;}}i:12;a:4:{s:1:\"a\";i:13;s:1:\"b\";s:21:\"peminjaman.kembalikan\";s:1:\"c\";s:3:\"web\";s:1:\"r\";a:1:{i:0;i:3;}}}s:5:\"roles\";a:3:{i:0;a:3:{s:1:\"a\";i:1;s:1:\"b\";s:5:\"admin\";s:1:\"c\";s:3:\"web\";}i:1;a:3:{s:1:\"a\";i:2;s:1:\"b\";s:7:\"petugas\";s:1:\"c\";s:3:\"web\";}i:2;a:3:{s:1:\"a\";i:3;s:1:\"b\";s:8:\"peminjam\";s:1:\"c\";s:3:\"web\";}}}', 1787635163);

-- --------------------------------------------------------

--
-- Struktur dari tabel `cache_locks`
--

CREATE TABLE `cache_locks` (
  `key` varchar(255) NOT NULL,
  `owner` varchar(255) NOT NULL,
  `expiration` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `detail_peminjaman`
--

CREATE TABLE `detail_peminjaman` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `peminjaman_id` bigint(20) UNSIGNED NOT NULL,
  `alat_id` bigint(20) UNSIGNED NOT NULL,
  `jumlah` int(11) NOT NULL,
  `kondisi_kembali` enum('baik','rusak_ringan','rusak_berat','hilang') DEFAULT NULL,
  `denda` decimal(12,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ;

--
-- Dumping data untuk tabel `detail_peminjaman`
--

INSERT INTO `detail_peminjaman` (`id`, `peminjaman_id`, `alat_id`, `jumlah`, `kondisi_kembali`, `denda`, `created_at`, `updated_at`) VALUES
(1, 1, 5, 1, NULL, 0.00, '2026-08-23 21:46:24', '2026-08-23 21:46:24'),
(2, 2, 3, 1, 'baik', 0.00, '2026-08-23 22:24:23', '2026-08-23 22:33:49'),
(3, 2, 12, 1, 'baik', 0.00, '2026-08-23 22:24:24', '2026-08-23 22:33:49'),
(4, 3, 3, 1, NULL, 0.00, '2026-08-23 22:24:43', '2026-08-23 22:24:43'),
(5, 4, 2, 1, NULL, 0.00, '2026-08-23 22:32:21', '2026-08-23 22:32:21');

-- --------------------------------------------------------

--
-- Struktur dari tabel `failed_jobs`
--

CREATE TABLE `failed_jobs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `uuid` varchar(255) NOT NULL,
  `connection` text NOT NULL,
  `queue` text NOT NULL,
  `payload` longtext NOT NULL,
  `exception` longtext NOT NULL,
  `failed_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `jobs`
--

CREATE TABLE `jobs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `queue` varchar(255) NOT NULL,
  `payload` longtext NOT NULL,
  `attempts` tinyint(3) UNSIGNED NOT NULL,
  `reserved_at` int(10) UNSIGNED DEFAULT NULL,
  `available_at` int(10) UNSIGNED NOT NULL,
  `created_at` int(10) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `job_batches`
--

CREATE TABLE `job_batches` (
  `id` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `total_jobs` int(11) NOT NULL,
  `pending_jobs` int(11) NOT NULL,
  `failed_jobs` int(11) NOT NULL,
  `failed_job_ids` longtext NOT NULL,
  `options` mediumtext DEFAULT NULL,
  `cancelled_at` int(11) DEFAULT NULL,
  `created_at` int(11) NOT NULL,
  `finished_at` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `kategori`
--

CREATE TABLE `kategori` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `nama` varchar(100) NOT NULL,
  `deskripsi` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `kategori`
--

INSERT INTO `kategori` (`id`, `nama`, `deskripsi`, `created_at`, `updated_at`) VALUES
(1, 'Perkakas Tangan', 'Obeng, tang, kunci, palu', '2026-08-23 21:22:44', '2026-08-23 21:22:44'),
(2, 'Alat Ukur', 'Multimeter, jangka sorong, mistar baja', '2026-08-23 21:22:44', '2026-08-23 21:22:44'),
(3, 'Perangkat Jaringan', 'Switch, router, tang crimping', '2026-08-23 21:22:45', '2026-08-23 21:22:45'),
(4, 'Perangkat Audio Visual', 'Proyektor, kamera, tripod', '2026-08-23 21:22:45', '2026-08-23 21:22:45');

-- --------------------------------------------------------

--
-- Struktur dari tabel `log_aktivitas`
--

CREATE TABLE `log_aktivitas` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` bigint(20) UNSIGNED DEFAULT NULL,
  `aksi` varchar(50) NOT NULL,
  `tabel_tujuan` varchar(50) DEFAULT NULL,
  `deskripsi` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `log_aktivitas`
--

INSERT INTO `log_aktivitas` (`id`, `user_id`, `aksi`, `tabel_tujuan`, `deskripsi`, `ip_address`, `created_at`) VALUES
(1, 2, 'setujui', 'peminjaman', 'Menyetujui peminjaman PJM-20260824-001', NULL, '2026-08-24 05:25:47'),
(2, 2, 'tolak', 'peminjaman', 'Menolak peminjaman PJM-20260824-003', '127.0.0.1', '2026-08-24 05:25:59'),
(3, 2, 'setujui', 'peminjaman', 'Menyetujui peminjaman PJM-20260824-002', NULL, '2026-08-24 05:26:05'),
(4, 3, 'ajukan_kembali', 'peminjaman', 'Mengajukan pengembalian PJM-20260824-002', '127.0.0.1', '2026-08-24 05:33:15'),
(5, 2, 'verifikasi_kembali', 'pengembalian', 'Memverifikasi pengembalian PJM-20260824-002 dengan total denda 0.00', NULL, '2026-08-24 05:33:49'),
(6, 3, 'ajukan_kembali', 'peminjaman', 'Mengajukan pengembalian PJM-20260824-001', '127.0.0.1', '2026-08-24 05:41:17');

-- --------------------------------------------------------

--
-- Struktur dari tabel `migrations`
--

CREATE TABLE `migrations` (
  `id` int(10) UNSIGNED NOT NULL,
  `migration` varchar(255) NOT NULL,
  `batch` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `migrations`
--

INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES
(1, '0001_01_01_000000_create_users_table', 1),
(2, '0001_01_01_000001_create_cache_table', 1),
(3, '0001_01_01_000002_create_jobs_table', 1),
(4, '2026_08_10_021325_add_two_factor_columns_to_users_table', 1),
(5, '2026_08_10_021326_create_passkeys_table', 1),
(6, '2026_08_10_024100_create_permission_tables', 1),
(7, '2026_08_10_032126_create_kategori_table', 1),
(8, '2026_08_10_032149_create_alat_table', 1),
(9, '2026_08_10_032206_create_peminjaman_table', 1),
(10, '2026_08_10_032222_create_detail_peminjaman_table', 1),
(11, '2026_08_10_032245_create_pengembalian_table', 1),
(12, '2026_08_10_032259_create_log_aktivitas_table', 1),
(13, '2026_08_10_032316_create_pengaturan_table', 1),
(14, '2026_08_24_031630_create_sp_setujui_peminjaman', 1),
(15, '2026_08_24_045208_create_fn_hitung_denda', 2),
(16, '2026_08_24_120000_update_fn_hitung_denda_add_jumlah_unit', 3),
(17, '2026_08_24_120100_create_trigger_pengembalian', 4);

-- --------------------------------------------------------

--
-- Struktur dari tabel `model_has_permissions`
--

CREATE TABLE `model_has_permissions` (
  `permission_id` bigint(20) UNSIGNED NOT NULL,
  `model_type` varchar(255) NOT NULL,
  `model_id` bigint(20) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `model_has_roles`
--

CREATE TABLE `model_has_roles` (
  `role_id` bigint(20) UNSIGNED NOT NULL,
  `model_type` varchar(255) NOT NULL,
  `model_id` bigint(20) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `model_has_roles`
--

INSERT INTO `model_has_roles` (`role_id`, `model_type`, `model_id`) VALUES
(1, 'App\\Models\\User', 1),
(2, 'App\\Models\\User', 2),
(3, 'App\\Models\\User', 3);

-- --------------------------------------------------------

--
-- Struktur dari tabel `passkeys`
--

CREATE TABLE `passkeys` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `name` varchar(255) NOT NULL,
  `credential_id` varchar(255) NOT NULL,
  `credential` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL CHECK (json_valid(`credential`)),
  `last_used_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `password_reset_tokens`
--

CREATE TABLE `password_reset_tokens` (
  `email` varchar(255) NOT NULL,
  `token` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Struktur dari tabel `peminjaman`
--

CREATE TABLE `peminjaman` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `kode_pinjam` varchar(20) NOT NULL,
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `petugas_id` bigint(20) UNSIGNED DEFAULT NULL,
  `tgl_pinjam` date NOT NULL,
  `tgl_harus_kembali` date NOT NULL,
  `tgl_diajukan_kembali` date DEFAULT NULL,
  `status` enum('diajukan','ditolak','dipinjam','menunggu_verifikasi','selesai') NOT NULL DEFAULT 'diajukan',
  `keperluan` text DEFAULT NULL,
  `alasan_tolak` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `peminjaman`
--

INSERT INTO `peminjaman` (`id`, `kode_pinjam`, `user_id`, `petugas_id`, `tgl_pinjam`, `tgl_harus_kembali`, `tgl_diajukan_kembali`, `status`, `keperluan`, `alasan_tolak`, `created_at`, `updated_at`) VALUES
(1, 'PJM-20260824-001', 3, 2, '2026-08-24', '2026-08-31', '2026-08-24', 'menunggu_verifikasi', 'jhgvhghghg', NULL, '2026-08-23 21:46:24', '2026-08-23 22:41:17'),
(2, 'PJM-20260824-002', 3, 2, '2026-08-24', '2026-08-31', '2026-08-24', 'selesai', 'bhgty', NULL, '2026-08-23 22:24:23', '2026-08-24 05:33:49'),
(3, 'PJM-20260824-003', 3, 2, '2026-08-24', '2026-08-31', NULL, 'ditolak', 'lllll', 'vggffdf', '2026-08-23 22:24:43', '2026-08-23 22:25:59'),
(4, 'PJM-20260824-004', 3, NULL, '2026-08-24', '2026-08-31', NULL, 'diajukan', 'gdfdfvdfdc', NULL, '2026-08-23 22:32:21', '2026-08-23 22:32:21');

-- --------------------------------------------------------

--
-- Struktur dari tabel `pengaturan`
--

CREATE TABLE `pengaturan` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `kunci` varchar(50) NOT NULL,
  `nilai` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `pengaturan`
--

INSERT INTO `pengaturan` (`id`, `kunci`, `nilai`, `created_at`, `updated_at`) VALUES
(1, 'tarif_denda_harian', '5000', '2026-08-23 21:22:44', '2026-08-23 21:22:44'),
(2, 'default_hari_pinjam', '7', '2026-08-23 21:22:44', '2026-08-23 21:22:44'),
(3, 'maks_hari_pinjam', '30', '2026-08-23 21:22:44', '2026-08-23 21:22:44'),
(4, 'nama_sekolah', 'SMK Negeri 1 Contoh', '2026-08-23 21:22:44', '2026-08-23 21:22:44');

-- --------------------------------------------------------

--
-- Struktur dari tabel `pengembalian`
--

CREATE TABLE `pengembalian` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `peminjaman_id` bigint(20) UNSIGNED NOT NULL,
  `petugas_id` bigint(20) UNSIGNED NOT NULL,
  `tgl_kembali` date NOT NULL,
  `hari_terlambat` int(11) NOT NULL DEFAULT 0,
  `denda` decimal(12,2) NOT NULL DEFAULT 0.00,
  `denda_kerusakan` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total_denda` decimal(12,2) NOT NULL DEFAULT 0.00,
  `catatan` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `pengembalian`
--

INSERT INTO `pengembalian` (`id`, `peminjaman_id`, `petugas_id`, `tgl_kembali`, `hari_terlambat`, `denda`, `denda_kerusakan`, `total_denda`, `catatan`, `created_at`, `updated_at`) VALUES
(1, 2, 2, '2026-08-24', 0, 0.00, 0.00, 0.00, NULL, '2026-08-23 22:33:49', '2026-08-23 22:33:49');

--
-- Trigger `pengembalian`
--
DELIMITER $$
CREATE TRIGGER `trg_pengembalian_after_insert` AFTER INSERT ON `pengembalian` FOR EACH ROW BEGIN
        DECLARE v_kode VARCHAR(20);

        UPDATE alat a
        JOIN detail_peminjaman d ON d.alat_id = a.id
        SET a.stok_tersedia = a.stok_tersedia + d.jumlah
        WHERE d.peminjaman_id = NEW.peminjaman_id
          AND d.kondisi_kembali IN ('baik', 'rusak_ringan');

        UPDATE alat a
        JOIN detail_peminjaman d ON d.alat_id = a.id
        SET a.stok = a.stok - d.jumlah
        WHERE d.peminjaman_id = NEW.peminjaman_id
          AND d.kondisi_kembali IN ('rusak_berat', 'hilang');

        UPDATE peminjaman
        SET status = 'selesai', updated_at = NOW()
        WHERE id = NEW.peminjaman_id;

        SELECT kode_pinjam INTO v_kode
        FROM peminjaman
        WHERE id = NEW.peminjaman_id;

        INSERT INTO log_aktivitas
            (user_id, aksi, tabel_tujuan, deskripsi, created_at)
        VALUES
            (NEW.petugas_id, 'verifikasi_kembali', 'pengembalian',
             CONCAT('Memverifikasi pengembalian ', v_kode,
                    ' dengan total denda ', NEW.total_denda), NOW());
    END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_pengembalian_before_insert` BEFORE INSERT ON `pengembalian` FOR EACH ROW BEGIN
        DECLARE v_tgl_harus_kembali DATE;
        DECLARE v_tarif DECIMAL(12, 2);
        DECLARE v_denda DECIMAL(12, 2);
        DECLARE v_hari INT;

        SELECT tgl_harus_kembali
        INTO v_tgl_harus_kembali
        FROM peminjaman
        WHERE id = NEW.peminjaman_id;

        SELECT CAST(nilai AS DECIMAL(12, 2))
        INTO v_tarif
        FROM pengaturan
        WHERE kunci = 'tarif_denda_harian';

        SET v_tarif = COALESCE(v_tarif, 0);
        SET v_hari = DATEDIFF(NEW.tgl_kembali, v_tgl_harus_kembali);
        SET v_hari = GREATEST(v_hari, 0);

        UPDATE detail_peminjaman
        SET denda = fn_hitung_denda(
            v_tgl_harus_kembali,
            NEW.tgl_kembali,
            jumlah,
            v_tarif
        )
        WHERE peminjaman_id = NEW.peminjaman_id;

        SELECT COALESCE(SUM(denda), 0)
        INTO v_denda
        FROM detail_peminjaman
        WHERE peminjaman_id = NEW.peminjaman_id;

        SET NEW.hari_terlambat = v_hari;
        SET NEW.denda = v_denda;
        SET NEW.total_denda = v_denda + COALESCE(NEW.denda_kerusakan, 0);
    END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktur dari tabel `permissions`
--

CREATE TABLE `permissions` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `name` varchar(255) NOT NULL,
  `guard_name` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `permissions`
--

INSERT INTO `permissions` (`id`, `name`, `guard_name`, `created_at`, `updated_at`) VALUES
(1, 'user.kelola', 'web', '2026-08-23 21:22:34', '2026-08-23 21:22:34'),
(2, 'alat.kelola', 'web', '2026-08-23 21:22:34', '2026-08-23 21:22:34'),
(3, 'kategori.kelola', 'web', '2026-08-23 21:22:34', '2026-08-23 21:22:34'),
(4, 'peminjaman.kelola', 'web', '2026-08-23 21:22:34', '2026-08-23 21:22:34'),
(5, 'pengembalian.kelola', 'web', '2026-08-23 21:22:34', '2026-08-23 21:22:34'),
(6, 'log.lihat', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(7, 'pengaturan.kelola', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(8, 'peminjaman.setujui', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(9, 'pengembalian.pantau', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(10, 'laporan.cetak', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(11, 'alat.lihat', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(12, 'peminjaman.ajukan', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35'),
(13, 'peminjaman.kembalikan', 'web', '2026-08-23 21:22:35', '2026-08-23 21:22:35');

-- --------------------------------------------------------

--
-- Struktur dari tabel `roles`
--

CREATE TABLE `roles` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `name` varchar(255) NOT NULL,
  `guard_name` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `roles`
--

INSERT INTO `roles` (`id`, `name`, `guard_name`, `created_at`, `updated_at`) VALUES
(1, 'admin', 'web', '2026-08-23 21:22:36', '2026-08-23 21:22:36'),
(2, 'petugas', 'web', '2026-08-23 21:22:36', '2026-08-23 21:22:36'),
(3, 'peminjam', 'web', '2026-08-23 21:22:37', '2026-08-23 21:22:37');

-- --------------------------------------------------------

--
-- Struktur dari tabel `role_has_permissions`
--

CREATE TABLE `role_has_permissions` (
  `permission_id` bigint(20) UNSIGNED NOT NULL,
  `role_id` bigint(20) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `role_has_permissions`
--

INSERT INTO `role_has_permissions` (`permission_id`, `role_id`) VALUES
(1, 1),
(2, 1),
(3, 1),
(4, 1),
(5, 1),
(6, 1),
(7, 1),
(8, 2),
(9, 2),
(10, 2),
(11, 3),
(12, 3),
(13, 3);

-- --------------------------------------------------------

--
-- Struktur dari tabel `sessions`
--

CREATE TABLE `sessions` (
  `id` varchar(255) NOT NULL,
  `user_id` bigint(20) UNSIGNED DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `payload` longtext NOT NULL,
  `last_activity` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `sessions`
--

INSERT INTO `sessions` (`id`, `user_id`, `ip_address`, `user_agent`, `payload`, `last_activity`) VALUES
('30wNEr3ljihWmQlK29EaW2wkTpI9calyTgJtIdHy', 2, '127.0.0.1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'YTo0OntzOjY6Il90b2tlbiI7czo0MDoiUXFyb3VEbnpOOGtLd01reHQwbEV1WkNaS0VkMHJWa2g5SFR2R3NyayI7czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDQ6Imh0dHA6Ly9sb2NhbGhvc3Q6ODAwMC9wZW5nZW1iYWxpYW4vcmluY2lhbi8xIjtzOjU6InJvdXRlIjtzOjIwOiJwZW5nZW1iYWxpYW4ucmluY2lhbiI7fXM6NTA6ImxvZ2luX3dlYl81OWJhMzZhZGRjMmIyZjk0MDE1ODBmMDE0YzdmNThlYTRlMzA5ODlkIjtpOjI7fQ==', 1787550464);

-- --------------------------------------------------------

--
-- Struktur dari tabel `users`
--

CREATE TABLE `users` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `nama` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `two_factor_secret` text DEFAULT NULL,
  `two_factor_recovery_codes` text DEFAULT NULL,
  `two_factor_confirmed_at` timestamp NULL DEFAULT NULL,
  `no_telp` varchar(20) DEFAULT NULL,
  `is_aktif` tinyint(1) NOT NULL DEFAULT 1,
  `remember_token` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data untuk tabel `users`
--

INSERT INTO `users` (`id`, `nama`, `username`, `email`, `password`, `two_factor_secret`, `two_factor_recovery_codes`, `two_factor_confirmed_at`, `no_telp`, `is_aktif`, `remember_token`, `created_at`, `updated_at`) VALUES
(1, 'Administrator', 'admin', 'admin@sekolah.sch.id', '$2y$12$tUO6CIHRO/WyVNFv.bsOjeVvgM3P8VEw2.Xg29pXL9.S3H7L01N5W', NULL, NULL, NULL, '081200000001', 1, NULL, '2026-08-23 21:22:40', '2026-08-23 21:22:40'),
(2, 'Petugas Laboratorium', 'petugas', 'petugas@sekolah.sch.id', '$2y$12$c16JruLi8zCXnGJ4xRUiiuTBQ6G2ELMDSCPnQVoTNzV.F3RGufvbC', NULL, NULL, NULL, '081200000002', 1, NULL, '2026-08-23 21:22:43', '2026-08-23 21:22:43'),
(3, 'Siswa Peminjam', 'peminjam', 'peminjam@sekolah.sch.id', '$2y$12$aPeMcPRQmvxqljguOn7HkeG9.G9DSGSW0TqlMfif6Ru3VJTnMReoe', NULL, NULL, NULL, '081200000003', 1, NULL, '2026-08-23 21:22:44', '2026-08-23 21:22:44');

--
-- Indexes for dumped tables
--

--
-- Indeks untuk tabel `alat`
--
ALTER TABLE `alat`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `alat_kode_alat_unique` (`kode_alat`),
  ADD KEY `alat_kategori_id_foreign` (`kategori_id`);

--
-- Indeks untuk tabel `cache`
--
ALTER TABLE `cache`
  ADD PRIMARY KEY (`key`),
  ADD KEY `cache_expiration_index` (`expiration`);

--
-- Indeks untuk tabel `cache_locks`
--
ALTER TABLE `cache_locks`
  ADD PRIMARY KEY (`key`),
  ADD KEY `cache_locks_expiration_index` (`expiration`);

--
-- Indeks untuk tabel `detail_peminjaman`
--
ALTER TABLE `detail_peminjaman`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `detail_peminjaman_peminjaman_id_alat_id_unique` (`peminjaman_id`,`alat_id`),
  ADD KEY `detail_peminjaman_alat_id_foreign` (`alat_id`);

--
-- Indeks untuk tabel `failed_jobs`
--
ALTER TABLE `failed_jobs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `failed_jobs_uuid_unique` (`uuid`);

--
-- Indeks untuk tabel `jobs`
--
ALTER TABLE `jobs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `jobs_queue_index` (`queue`);

--
-- Indeks untuk tabel `job_batches`
--
ALTER TABLE `job_batches`
  ADD PRIMARY KEY (`id`);

--
-- Indeks untuk tabel `kategori`
--
ALTER TABLE `kategori`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `kategori_nama_unique` (`nama`);

--
-- Indeks untuk tabel `log_aktivitas`
--
ALTER TABLE `log_aktivitas`
  ADD PRIMARY KEY (`id`),
  ADD KEY `log_aktivitas_user_id_foreign` (`user_id`),
  ADD KEY `log_aktivitas_created_at_index` (`created_at`);

--
-- Indeks untuk tabel `migrations`
--
ALTER TABLE `migrations`
  ADD PRIMARY KEY (`id`);

--
-- Indeks untuk tabel `model_has_permissions`
--
ALTER TABLE `model_has_permissions`
  ADD PRIMARY KEY (`permission_id`,`model_id`,`model_type`),
  ADD KEY `model_has_permissions_model_id_model_type_index` (`model_id`,`model_type`);

--
-- Indeks untuk tabel `model_has_roles`
--
ALTER TABLE `model_has_roles`
  ADD PRIMARY KEY (`role_id`,`model_id`,`model_type`),
  ADD KEY `model_has_roles_model_id_model_type_index` (`model_id`,`model_type`);

--
-- Indeks untuk tabel `passkeys`
--
ALTER TABLE `passkeys`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `passkeys_credential_id_unique` (`credential_id`),
  ADD KEY `passkeys_user_id_index` (`user_id`);

--
-- Indeks untuk tabel `password_reset_tokens`
--
ALTER TABLE `password_reset_tokens`
  ADD PRIMARY KEY (`email`);

--
-- Indeks untuk tabel `peminjaman`
--
ALTER TABLE `peminjaman`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `peminjaman_kode_pinjam_unique` (`kode_pinjam`),
  ADD KEY `peminjaman_user_id_foreign` (`user_id`),
  ADD KEY `peminjaman_petugas_id_foreign` (`petugas_id`),
  ADD KEY `peminjaman_status_index` (`status`);

--
-- Indeks untuk tabel `pengaturan`
--
ALTER TABLE `pengaturan`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `pengaturan_kunci_unique` (`kunci`);

--
-- Indeks untuk tabel `pengembalian`
--
ALTER TABLE `pengembalian`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `pengembalian_peminjaman_id_unique` (`peminjaman_id`),
  ADD KEY `pengembalian_petugas_id_foreign` (`petugas_id`);

--
-- Indeks untuk tabel `permissions`
--
ALTER TABLE `permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `permissions_name_guard_name_unique` (`name`,`guard_name`);

--
-- Indeks untuk tabel `roles`
--
ALTER TABLE `roles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `roles_name_guard_name_unique` (`name`,`guard_name`);

--
-- Indeks untuk tabel `role_has_permissions`
--
ALTER TABLE `role_has_permissions`
  ADD PRIMARY KEY (`permission_id`,`role_id`),
  ADD KEY `role_has_permissions_role_id_foreign` (`role_id`);

--
-- Indeks untuk tabel `sessions`
--
ALTER TABLE `sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `sessions_user_id_index` (`user_id`),
  ADD KEY `sessions_last_activity_index` (`last_activity`);

--
-- Indeks untuk tabel `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `users_username_unique` (`username`),
  ADD UNIQUE KEY `users_email_unique` (`email`);

--
-- AUTO_INCREMENT untuk tabel yang dibuang
--

--
-- AUTO_INCREMENT untuk tabel `alat`
--
ALTER TABLE `alat`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT untuk tabel `detail_peminjaman`
--
ALTER TABLE `detail_peminjaman`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT untuk tabel `failed_jobs`
--
ALTER TABLE `failed_jobs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT untuk tabel `jobs`
--
ALTER TABLE `jobs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT untuk tabel `kategori`
--
ALTER TABLE `kategori`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT untuk tabel `log_aktivitas`
--
ALTER TABLE `log_aktivitas`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT untuk tabel `migrations`
--
ALTER TABLE `migrations`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT untuk tabel `passkeys`
--
ALTER TABLE `passkeys`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT untuk tabel `peminjaman`
--
ALTER TABLE `peminjaman`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT untuk tabel `pengaturan`
--
ALTER TABLE `pengaturan`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT untuk tabel `pengembalian`
--
ALTER TABLE `pengembalian`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT untuk tabel `permissions`
--
ALTER TABLE `permissions`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT untuk tabel `roles`
--
ALTER TABLE `roles`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT untuk tabel `users`
--
ALTER TABLE `users`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Ketidakleluasaan untuk tabel pelimpahan (Dumped Tables)
--

--
-- Ketidakleluasaan untuk tabel `alat`
--
ALTER TABLE `alat`
  ADD CONSTRAINT `alat_kategori_id_foreign` FOREIGN KEY (`kategori_id`) REFERENCES `kategori` (`id`);

--
-- Ketidakleluasaan untuk tabel `detail_peminjaman`
--
ALTER TABLE `detail_peminjaman`
  ADD CONSTRAINT `detail_peminjaman_alat_id_foreign` FOREIGN KEY (`alat_id`) REFERENCES `alat` (`id`),
  ADD CONSTRAINT `detail_peminjaman_peminjaman_id_foreign` FOREIGN KEY (`peminjaman_id`) REFERENCES `peminjaman` (`id`) ON DELETE CASCADE;

--
-- Ketidakleluasaan untuk tabel `log_aktivitas`
--
ALTER TABLE `log_aktivitas`
  ADD CONSTRAINT `log_aktivitas_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Ketidakleluasaan untuk tabel `model_has_permissions`
--
ALTER TABLE `model_has_permissions`
  ADD CONSTRAINT `model_has_permissions_permission_id_foreign` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`id`) ON DELETE CASCADE;

--
-- Ketidakleluasaan untuk tabel `model_has_roles`
--
ALTER TABLE `model_has_roles`
  ADD CONSTRAINT `model_has_roles_role_id_foreign` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE;

--
-- Ketidakleluasaan untuk tabel `passkeys`
--
ALTER TABLE `passkeys`
  ADD CONSTRAINT `passkeys_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Ketidakleluasaan untuk tabel `peminjaman`
--
ALTER TABLE `peminjaman`
  ADD CONSTRAINT `peminjaman_petugas_id_foreign` FOREIGN KEY (`petugas_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `peminjaman_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`);

--
-- Ketidakleluasaan untuk tabel `pengembalian`
--
ALTER TABLE `pengembalian`
  ADD CONSTRAINT `pengembalian_peminjaman_id_foreign` FOREIGN KEY (`peminjaman_id`) REFERENCES `peminjaman` (`id`),
  ADD CONSTRAINT `pengembalian_petugas_id_foreign` FOREIGN KEY (`petugas_id`) REFERENCES `users` (`id`);

--
-- Ketidakleluasaan untuk tabel `role_has_permissions`
--
ALTER TABLE `role_has_permissions`
  ADD CONSTRAINT `role_has_permissions_permission_id_foreign` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `role_has_permissions_role_id_foreign` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
