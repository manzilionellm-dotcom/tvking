import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/channels/domain/channel_category_index.dart';

void main() {
  test('25 000 chaînes : parcourues une fois, aucune relecture pendant 10 000 changements de catégorie', () {
    final List<Channel> channels = <Channel>[
      for (int i=0; i<25000; i++) Channel(id:'$i', name:'Chaîne $i',
        category:'Groupe ${i%100}', streamUrl:'https://source.invalid/$i.ts', isLive:true),
    ];
    int reads=0;
    final ChannelCategoryIndex index=ChannelCategoryIndex(channels,
      categoryOf:(Channel c) { reads++; return c.category; });
    expect(reads,25000);
    expect(index.categories.first,'Groupe 0');
    final List<Channel> first=index.channelsIn('Groupe 0');
    for (int i=0; i<10000; i++) {
      expect(index.countIn('Groupe ${i%100}'),250);
      expect(index.channelsIn('Groupe ${i%100}'),hasLength(250));
    }
    expect(reads,25000);
    expect(identical(first,index.channelsIn('Groupe 0')),isTrue);
    expect(first.take(2).map((Channel c)=>c.id),<String>['0','100']);
    expect(index.channelsIn('Absente'),isEmpty);
  });
}
