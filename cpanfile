requires 'perl', '5.036';
requires 'DBIx::Class';
requires 'Moose';
requires 'MooseX::NonMoose';
requires 'MooseX::MarkAsMethods';
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
