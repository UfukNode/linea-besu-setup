# Linea Besu Node Kurulum Rehberi (MetaMask RPC)

Bu rehberde, Ubuntu sunucusu üzerinde **Linea ağı için Besu node** kurulumunu adım adım anlatıyorum.
Kurulum sonrası kendi RPC’nizi MetaMask’e ekleyebilir ve dilediğiniz gibi kullanabilirsiniz.

| Bileşen     | Minimum Gereksinim |
| ----------- | ------------------ |
| **İşlemci** | Min. 4 vCPU        |
| **RAM**     | Min. 8 GB          |
| **Disk**    | Min. 400 GB SSD    |

---

## Bu Node’u Neden Kuruyoruz?

Linea ağı üzerinde çalışan kendi RPC node’unuz sayesinde:

* MetaMask üzerinden daha hızlı ve güvenli işlem yapabilirsiniz.
* Dışarıya açarak arkadaşlarınıza/kendi topluluğunuza RPC sağlayabilirsiniz.
* Merkeziyetsiz ağlara katkı sunarsınız.

---

## Kurulum Adımları

### 1. Script’i İndir ve Çalıştır

```bash
wget https://raw.githubusercontent.com/UfukNode/linea-besu-setup/refs/heads/main/script.sh
chmod 777 ./script.sh
./script.sh
```

<img width="1677" height="303" alt="image" src="https://github.com/user-attachments/assets/9b59e3fd-b3e5-4682-b1f7-e12ff959c548" />

Kurulum başladığında sizden bazı sorular sorulacak 👇

---

## Script Sırasında Sorulacak Sorular

1. **RPC’yi internete açmak ister misiniz?** → Eğer RPC’nizi paylaşmak istiyorsanız `y`, sadece kendiniz kullanacaksanız `n`.
2. **Nginx server\_name (domain veya IP)** → Domaininiz yoksa IP adresinizi girin.

✅ Sonrasında script otomatik olarak Besu + güvenlik ayarlarını yapacak.

<img width="711" height="108" alt="image" src="https://github.com/user-attachments/assets/5737da75-17b0-4118-9d9c-0ed881ff5d03" />
<img width="634" height="99" alt="Ekran görüntüsü 2025-08-31 144015" src="https://github.com/user-attachments/assets/c1ad74ec-7e7a-4bbc-9157-eb30fa13d977" />

---

## Logları Takip Et:

```bash
sudo journalctl -f -u besu
```

Ortalama 8-10 saatte sekronize olacaktır ve loglardan takip edebilirsiniz. Loglar aşağıdaki gibi görünmelidir.

<img width="1513" height="189" alt="image" src="https://github.com/user-attachments/assets/3fac9c7b-9046-4ca0-8446-9e7397ea5646" />

---

## MetaMask Ayarları

Kurulum tamamlandıktan sonra MetaMask’te yeni RPC ekleyin:

```
Network Name : Linea Mainnet (Local Node)
New RPC URL  : http://SUNUCU_IP:8545
Chain ID     : 59144
Currency     : ETH
Explorer     : https://lineascan.build
```

> Eğer testnet (Sepolia) kurduysanız:
> Chain ID: `59141` | Explorer: `https://sepolia.lineascan.build`

---

## Faydalı Komutlar

Logları izlemek için:

```bash
sudo journalctl -f -u besu
```

Node’u yeniden başlatmak için:

```bash
sudo systemctl restart besu
```

Node’u durdurmak için:

```bash
sudo systemctl stop besu
```

Node’u kaldırmak için:

```bash
sudo ./script.sh --uninstall
```

---

## Senkronizasyon Kontrolü

Node’un senkronize olup olmadığını test edin:

```bash
curl -s -X POST http://127.0.0.1:8545 \
-H "Content-Type: application/json" \
-d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

* `"result": false` → Node senkronize oldu.
* Aksi halde senkronize olmaya devam ediyor.

---

## Güvenlik Notları

* RPC portunu **herkese açık bırakmayın**. Sadece güvendiğiniz kişilere verin.
* Nginx reverse proxy + UFW kullanarak güvenliği artırın.
* 10-20 kişi aynı anda kullanabilir (sunucuya göre kapasite değişir).

---
