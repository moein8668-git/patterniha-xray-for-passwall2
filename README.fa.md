<div dir="rtl">

# هسته Xray «patterniha» برای PassWall2 (OpenWrt)

[English](README.md) | [فارسی](README.fa.md)

## ❤️ تشکر ویژه از patterniha

**همه اعتبار این هسته متعلق به [patterniha](https://github.com/patterniha) است.**
او هسته سفارشی Xray ([patterniha/xray-core](https://github.com/patterniha/xray-core)) و کلاینت‌هایش را می‌سازد و نگه می‌دارد:
[PattN](https://github.com/patterniha/PattN) (دسکتاپ) و [PattNG](https://github.com/patterniha/PattNG) (اندروید).
این ریپو **هیچ کدی از او ندارد** و فقط یک نصب‌کننده کوچک است که ریلیز رسمی او را دانلود می‌کند و روی OpenWrt اجرا می‌کند.
لطفاً از پروژه‌هایش حمایت کنید و ستاره بدهید.

> ⚠️ **این اسکریپت کاملاً وایب‌کد شده است** (با دستیار هوش مصنوعی نوشته شده). فقط روی یک ماشین مجازی x86_64 با OpenWrt 25.12 تست شده.
> قبل از اجرا با دسترسی root آن را بخوانید و با مسئولیت خودتان استفاده کنید.

## این چیست

بازنویسی Xray نیست. `pattx` یک اسکریپت شل حدود ۲۰۰ خطی است که:

- معماری روتر را تشخیص می‌دهد (x86، arm، mips، mipsel، riscv64، loong64 و ...)
- ریلیز رسمی مناسب را از `patterniha/xray-core` می‌گیرد و SHA-256 را بررسی می‌کند
- آن را در `/opt/pattx` با سرویس procd نصب می‌کند (اجرا با بوت و ری‌استارت خودکار)
- در صورت تمایل **PassWall2** را به‌جای xray استاندارد روی این هسته می‌برد
- آپدیت و بازگشت به نسخه قبل را با یک دستور انجام می‌دهد

هسته همان هسته PattN و PattNG است، پس قابلیت‌های اضافه‌ای که او به هسته داده از طریق کانفیگ JSON معمولی Xray روی روتر هم در دسترس است.

## نصب

روی روتر (نیاز به اینترنت و دسترسی به GitHub؛ `curl` یا `wget`؛ اگر `unzip` نبود خودکار نصب می‌شود):

```sh
wget -O /tmp/pattx.sh https://raw.githubusercontent.com/moein8668-git/patterniha-xray-for-passwall2/main/pattx.sh
sh /tmp/pattx.sh install
```

یا از ویندوز (SSH با root به روتر):

```powershell
.\install.ps1 -Router 192.168.1.1
```

نتیجه پیش‌فرض: SOCKS5 روی `:10808` (با UDP)، HTTP روی `:10809`، بدون احراز هویت (اگر روتر در دسترس بیرون است به LAN محدودش کنید).

## دستورها

```
pattx update               آپدیت به آخرین ریلیز (اگر همان باشد کاری نمی‌کند)
pattx update v26.10.9      نصب نسخه مشخص
pattx rollback             برگشت به هسته قبلی
pattx status               ورژن، سرویس، پورت‌ها، مسیر PassWall2
pattx passwall on|off      استفاده در PassWall2 / برگشت به xray استاندارد
pattx ech                  DNS نودهای ECH در PassWall2 را direct می‌کند (خودکار هم انجام می‌شود)
pattx auto on|off          آپدیت خودکار روزانه (cron، ساعت ۰۴:۱۷)
pattx uninstall
```

## پروکسی محلی مستقل

کانفیگ JSON خودتان را در `/opt/pattx/config.json` بگذارید، بعد:

```sh
/opt/pattx/xray run -test -c /opt/pattx/config.json && /etc/init.d/pattx restart
```

## استفاده در PassWall2

```sh
pattx passwall on     # مسیر xray در PassWall2 را روی /opt/pattx/xray می‌گذارد
```

**شیم سازگاری (فقط برای PassWall2 قدیمی‌تر از 26.10):** هسته‌های جدید Xray (از جمله این یکی) فیلد `proxySettings` را از outbound حذف کرده‌اند
(جایگزین: `streamSettings.sockopt.dialerProxy`) ولی PassWall2 نسخه 26.8.x هنوز آن را می‌نویسد، برای همین هسته بالا نمی‌آید
(وضعیت «Core NOT RUNNING»). دستور `pattx passwall on` یک شیم کوچک به `/usr/lib/lua/luci/passwall2/util_xray.lua` اضافه می‌کند
که این فیلد را تبدیل می‌کند؛ `pattx passwall off` و `uninstall` فایل اصلی را برمی‌گردانند (نسخه پشتیبان: `util_xray.lua.pattx.bak`).
آپگرید PassWall2 فایل را بازنویسی می‌کند، پس بعدش دوباره `pattx passwall on` (یا `pattx update`) بزنید.
PassWall2 نسخه 26.10.1 به بعد خودش از `dialerProxy` استفاده می‌کند و شیم خودکار رد می‌شود (روی 26.10.1 تست شده).

PassWall2 کانفیگ را خودش می‌سازد؛ فیلدی که فقط در هسته patterniha هست باید در ویرایشگر نود PassWall2 پذیرفته شود.
دکمه «آپدیت Xray» خود PassWall2 را نزنید چون هسته را عوض می‌کند. به‌جایش `pattx update` بزنید.

## نودهای ECH (خودکار)

نودهای ECH (مثل `echConfigList: cloudflare-ech.com+udp://8.8.8.8`) باعث می‌شوند هسته رکورد ECH را از آن DNS بگیرد.
روی روتر این کوئری از خود روتر خارج می‌شود و پروکسی شفاف PassWall2 آن را به همان نود می‌فرستد، در حالی که نود برای وصل شدن به ECH نیاز دارد: یک حلقه
(خطای `Failed to query ECH DNS record ... i/o timeout` در لاگ xray پس‌وال).

`pattx` این را خودکار حل می‌کند: دستور `pattx ech` سرور DNS مربوط به ECH هر نود PassWall2 را می‌خواند و به لیست Direct IP پس‌وال
(`/usr/share/passwall2/direct_ip`) اضافه می‌کند و اگر چیزی عوض شد PassWall2 را ری‌استارت می‌کند. خودش اجرا می‌شود:
- وقتی در LuCI تنظیمات PassWall2 را ذخیره/اعمال می‌کنید (تریگر `config.change` در procd، پس نودهای ECH جدید هم پوشش داده می‌شوند)
- هنگام بالا آمدن سرویس `pattx` (بوت) و با `pattx install` / `pattx update` / `pattx passwall on`

نکته: آپگرید پکیج PassWall2 فایل `direct_ip` را بازنویسی می‌کند؛ بعدش `pattx ech` (یا `pattx update`) بزنید.
اگر در `ech_config` اسم دامنه باشد (مثل `https://dns.google/dns-query`) هنگام همگام‌سازی resolve می‌شود و IPv4هایش اضافه می‌شوند.

## عیب‌یابی: روتر با نودِ پشت Cloudflare نمی‌تواند DNS بگیرد

اگر نود پشت Cloudflare (Workers/CDN) باشد، DNS روی TCP به آی‌پی‌های خود Cloudflare مثل `1.1.1.1:53` از طریق آن ممکن است خطا بدهد
(`failed to read response length ... closed pipe`) و تا وقتی PassWall2 روشن است روتر DNS ندارد، حتی `pattx update` هم به GitHub نمی‌رسد.
برای Remote DNS از DoH استفاده کنید: PassWall2 > Basic Settings > DNS > پروتکل Remote DNS برابر `DoH`،
مثلاً `https://dns.google/dns-query,8.8.8.8`. اگر گیر کردید: `/etc/init.d/passwall2 stop`، بعد `pattx update`، بعد دوباره PassWall2 را روشن کنید.

## محدودیت‌ها

- فقط هسته Xray. نسخه‌های `sing-box` و `mihomo` او استفاده نمی‌شوند (نیاز به glibc / CPU نسل v3).
- فقط x86_64 با OpenWrt 25.12 تست شده. معماری‌های دیگر در اسکریپت نگاشت شده‌اند ولی تست نشده‌اند.
- روتر برای آپدیت باید به github.com دسترسی داشته باشد.

## مجوز و اعتبار

اسکریپت‌های این ریپو: MIT. هسته Xray از patterniha و [XTLS/Xray-core](https://github.com/XTLS/Xray-core) (مجوز MPL-2.0) است
و از ریلیزهای خودشان دانلود می‌شود و در این ریپو بازتوزیع نمی‌شود.

</div>
