requires 'perl', '5.036';
requires 'DBIx::Class';
requires 'DBD::SQLite';
requires 'Template';
requires 'JSON::MaybeXS';
requires 'Path::Tiny';
requires 'Image::Magick';
requires 'Image::ExifTool';
requires 'URI';
requires 'HTML::Entities';

on 'test' => sub {
  requires 'Test::More';
};

on 'develop' => sub {
  requires 'DBIx::Class::Schema::Loader';
  requires 'App::HTTPThis';
};
