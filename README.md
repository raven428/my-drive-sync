# my-drive-sync
google drive downloader for local backups

## installation
```bash
curl -L https://install.perlbrew.pl | bash
perlbrew init
perlbrew install perl-5.18.4 -j 9
perlbrew install-cpanm
perlbrew lib create perl-5.18.4@gdrive
perlbrew use perl-5.18.4@gdrive
cpanm Net::Google::Drive::Simple DateTime DateTime::Format::RFC3339
```
then you need to [make](https://metacpan.org/pod/Net::Google::Drive::Simple#GETTING-STARTED) token for access goole drive, then
```bash
perlbrew exec --with perl-5.18.4@gdrive ./my-drive-sync.pl
```

## usage
```bash
my-drive-sync.pl \
  --dstdir /usr/nfs/google-drive/raven428 \
[ --exclude acr \]
[ --delete ]
```
`---dstdir` - destination directory;

`--exclude` - regular expressions for exclude scanning remote directories;

`--delete` - delete local files, removed from drive;
