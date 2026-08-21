# colorburst

colorburst là một hệ điều hành tự do dành cho máy tính cá nhân. Bạn có thể cài
đặt, sử dụng, sao chép và chỉnh sửa nó một cách hợp pháp, không phải trả phí
bản quyền cho bất kỳ ai.

Hệ thống được xây dựng từ mã nguồn của **ChromiumOS** — phần mã nguồn mở mà
Google phát hành, cũng là nền tảng của ChromeOS chạy trên các máy Chromebook.
colorburst không phải là ChromeOS và không liên kết với Google.

> **Đây là bản thử nghiệm.** Dự án đang ở giai đoạn đầu, nên đừng kỳ vọng mọi
> thứ chạy trơn tru. Nhiều chỗ trong giao diện vẫn tự xưng là "Chrome" hoặc
> "Chromium" — phần thương hiệu chưa được thay hết, không phải cố ý.

## Dành cho ai

colorburst hướng tới sự đơn giản: học sinh – sinh viên, nhân viên văn phòng và
người lớn tuổi. Máy có trình duyệt và những thứ cần thiết, không có gì phải học
thêm, cũng không có gì để cấu hình.

Chạy được trên máy để bàn hoặc laptop sản xuất trong khoảng **10 năm trở lại
đây**.

## Điểm khác biệt chính

- **Tài khoản cục bộ.** Ngay trong lần khởi động đầu tiên, bạn tự tạo một tài
  khoản nằm trên chính máy của mình. Không cần tài khoản Google, không cần kết
  nối mạng để đăng nhập.
- **Giao diện tiếng Việt** được đặt làm mặc định.
- **Gõ tiếng Việt có sẵn** — Telex (mặc định), VNI và VIQR, không cần cài thêm
  gì. Chuyển đổi bằng biểu tượng **VI** ở góc dưới bên phải, hoặc Ctrl + Space.
- **Tự cập nhật.** Máy nhận các bản vá qua máy chủ cập nhật của colorburst,
  không qua Google.

## Dùng thử từ USB

Cách này chạy trên máy thật mà chưa cần cài đặt.

1. Tải tệp ảnh đĩa (`colorburst-<phiên bản>.bin.xz`) ở mục **Releases** trên
   GitHub và chuẩn bị một USB dung lượng từ **16 GB**.
2. Ghi tệp ảnh đĩa vào USB.

   **Windows / macOS:** dùng [balenaEtcher](https://etcher.balena.io/) — chọn
   thẳng tệp `.xz`, chương trình tự giải nén rồi ghi.

   **Linux:**

   ```bash
   unxz colorburst-<phiên bản>.bin.xz
   sudo dd if=colorburst-<phiên bản>.bin of=/dev/sdX bs=4M status=progress conv=fsync
   ```

   Thay `/dev/sdX` bằng USB của bạn. **Ghi nhầm ổ sẽ xoá sạch dữ liệu ổ đó** —
   hãy kiểm tra kỹ bằng `lsblk`.
3. Khởi động máy từ USB (thường bấm F12, F2 hoặc Esc lúc mới bật máy). Bạn có
   thể cần tắt **Secure Boot** trong BIOS/UEFI.

Chạy từ USB không đụng gì đến ổ cứng trong máy.

## Cài đặt vào máy

Khởi động từ USB như trên, rồi chọn mục cài đặt trên màn hình chào.

**Việc cài đặt sẽ xoá toàn bộ ổ đĩa được chọn.** Hãy sao lưu trước.

## Tài khoản

Lần đầu khởi động, màn hình chào sẽ hỏi bạn muốn **dùng thử** hay **cài đặt**.
Sau khi chọn, máy hỏi bạn muốn thiết lập theo cách nào — hãy chọn
**"Create a local account"**, đặt một cái tên, rồi đặt mật khẩu.

Tài khoản đó nằm trên máy của bạn. Không có tài khoản Google, không có gì được
gửi đi đâu cả, và bạn đăng nhập được kể cả khi không có mạng.

Nếu quên mật khẩu thì không có cách khôi phục — hiện chưa có, vì không có máy
chủ nào giữ tài khoản giúp bạn.

## Tự biên dịch

colorburst được biên dịch trong Docker, không cài gì lên máy chủ. Toàn bộ công
cụ nằm ở kho `chromiumos-devenv`, kèm hướng dẫn chi tiết.

```bash
./cros-sdk.sh bash -lc 'cd ~/chromiumos && cros_sdk -- cros build-packages --board=amd64-generic'
./cros-sdk.sh bash -lc 'cd ~/chromiumos && cros_sdk -- cros build-image --board=amd64-generic test'
```

Ảnh đĩa sau khi biên dịch nằm ở:

```
chromiumos/src/build/images/amd64-generic/latest/chromiumos_test_image.bin
```

Máy biên dịch cần khoảng **200 GB ổ trống** và nhiều giờ cho lần đầu.

## Tham gia phát triển

Còn rất nhiều việc phải làm. Nếu bạn biết Linux và muốn góp sức xây dựng, rất
hoan nghênh — từ báo lỗi, dịch thuật, cho tới viết mã.

Discord: _(sẽ cập nhật)_

## Hạn chế / TODO

- **Chưa khôi phục được mật khẩu** nếu bạn quên.
- Chạy thử trong máy ảo hiện chỉ dành cho người phát triển, chưa dùng được cho
  người thường — hãy dùng USB.
- Nội dung có bản quyền số (DRM) — Netflix và tương tự chưa xem được.
- Chưa tăng tốc giải mã video bằng phần cứng, nên video nặng sẽ tốn pin hơn.
- Bộ gõ tiếng Việt mới ở mức cơ bản; người quen gõ nhanh sẽ thấy còn vụng.
- Phần thương hiệu chưa thay hết: màn hình khởi động và vài chỗ vẫn là Chromium.

## Nguồn gốc và giấy phép

colorburst là một bản phân nhánh (fork) của ChromiumOS. Mã nguồn gốc thuộc về
các tác giả ChromiumOS và được phát hành theo giấy phép BSD 3 điều khoản; các
thành phần khác giữ nguyên giấy phép của chúng.

Dự án không có liên hệ với Google. "Chrome", "ChromeOS" và "Chromebook" là
thương hiệu của Google.

## Về cái tên

Trên truyền hình analog màu (NTSC, PAL), mỗi dòng quét đều mở đầu bằng một đoạn
tín hiệu ngắn gọi là *colorburst* — vài chu kỳ của sóng mang màu, khoảng
3,58 MHz với NTSC. Bản thân nó không mang hình ảnh; nhiệm vụ duy nhất của nó là
cho bộ dao động trong máy thu một mốc pha để so. Không có đoạn tín hiệu đó, máy
thu vẫn hiện hình nhưng màu sẽ sai.

Một tín hiệu tham chiếu nhỏ, lặp lại đều đặn, để phần còn lại hiển thị đúng.
