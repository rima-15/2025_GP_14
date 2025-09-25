import 'package:flutter/material.dart';
import 'package:madar_app/screens/venue_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() =>
      HomePageState();
}

class HomePageState
    extends State<HomePage> {
  final Color activeColor = const Color(
    0xFF787E65,
  );

  final List<String> filters = const [
    'All',
    'Malls',
    'Stadiums',
    'Airports',
  ];

  final List<VenueData> venues = const [
    VenueData(
      name: 'Solitaire Mall',
      type: 'Shopping Mall',
      distance: '2.3 km',
      imageUrl:
          'images/SolitaireVenue.jpeg',
      category: 'Malls',
      rating: 4.6,
    ),
    VenueData(
      name: 'Riyadh Park Mall',
      type: 'Shopping Mall',
      distance: '5.1 km',
      imageUrl:
          'images/RiyadhPark.jpeg',
      category: 'Malls',
      rating: 4.5,
    ),
    VenueData(
      name: 'King Fahd Stadium',
      type: 'Sports Stadium',
      distance: '9.4 km',
      imageUrl:
          'images/KingFahadStadium.jpeg',
      category: 'Stadiums',
      rating: 4.3,
    ),
    VenueData(
      name:
          'King Khalid International Airport',
      type: 'Airport',
      distance: '25.8 km',
      imageUrl:
          'images/KingKhalidAirport.jpeg',
      category: 'Airports',
      rating: 4.1,
    ),
  ];

  int selectedFilterIndex = 0;
  String _query = '';

  List<VenueData> get filteredVenues {
    if (selectedFilterIndex == 0 &&
        _query.isEmpty)
      return venues;
    final selected =
        filters[selectedFilterIndex];
    return venues.where((v) {
      final matchFilter =
          (selected == 'All') ||
          v.category == selected;
      final q = _query.toLowerCase();
      final matchSearch =
          _query.isEmpty ||
          v.name.toLowerCase().contains(
            q,
          ) ||
          v.type.toLowerCase().contains(
            q,
          );
      return matchFilter && matchSearch;
    }).toList();
  }

  void setCategory(String cat) {
    final idx = filters.indexOf(cat);
    if (idx != -1)
      setState(
        () => selectedFilterIndex = idx,
      );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterTabs(),
        Expanded(
          child: _buildVenueList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey
                .withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (q) =>
            setState(() => _query = q),
        decoration: const InputDecoration(
          hintText:
              'Search for a venue ...',
          prefixIcon: Icon(
            Icons.search,
            color: Colors.grey,
          ),
          border: InputBorder.none,
          contentPadding:
              EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 35,
      margin:
          const EdgeInsets.symmetric(
            horizontal: 16,
          ),
      child: ListView.builder(
        scrollDirection:
            Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final isSelected =
              selectedFilterIndex ==
              index;
          return GestureDetector(
            onTap: () => setState(
              () =>
                  selectedFilterIndex =
                      index,
            ),
            child: Container(
              margin:
                  const EdgeInsets.only(
                    right: 12,
                  ),

              padding:
                  const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor
                    : Colors.grey[200],
                borderRadius:
                    BorderRadius.circular(
                      25,
                    ),
              ),
              child: Center(
                child: Text(
                  filters[index],
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors
                              .grey[700],
                    fontWeight:
                        isSelected
                        ? FontWeight
                              .w600
                        : FontWeight
                              .normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVenueList() {
    return ListView.builder(
      itemCount: filteredVenues.length,
      itemBuilder: (context, index) =>
          _buildVenueCard(
            filteredVenues[index],
          ),
    );
  }

  void _openVenue(VenueData v) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePage(
          name: v.name,
          image: v.imageUrl,
          description: _descriptionFor(
            v,
          ),
        ),
      ),
    );
  }

  String _descriptionFor(VenueData v) {
    if (v.name.contains('Solitaire')) {
      return 'Solitaire Mall is a premier shopping destination in Riyadh offering fashion, dining, and entertainment in a modern space.';
    }
    if (v.name.contains(
      'Riyadh Park',
    )) {
      return 'Riyadh Park Mall features a wide range of retail stores, cafes, and family entertainment options.';
    }
    if (v.category == 'Stadiums') {
      return 'A multi-purpose stadium hosting major sporting events and concerts.';
    }
    if (v.category == 'Airports') {
      return 'A major international airport connecting Riyadh to the world.';
    }
    return 'Discover shops, cafes, and more.';
  }

  Widget _buildVenueCard(VenueData v) {
    return InkWell(
      onTap: () => _openVenue(v),
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        margin:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey
                  .withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(
                0,
                2,
              ),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
              child: Image.asset(
                v.imageUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                      12,
                    ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      v.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w600,
                        color: Colors
                            .black87,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      v.type,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors
                            .grey[600],
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors
                              .amber[700],
                          size: 18,
                        ),
                        const SizedBox(
                          width: 4,
                        ),
                        Text(
                          v.rating
                              .toString(),
                          style: TextStyle(
                            fontSize:
                                14,
                            color: Colors
                                .grey[700],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          v.distance,
                          style: TextStyle(
                            fontSize:
                                14,
                            color: Colors
                                .grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VenueData {
  final String name;
  final String type;
  final String distance;
  final String imageUrl;
  final String category;
  final double rating;

  const VenueData({
    required this.name,
    required this.type,
    required this.distance,
    required this.imageUrl,
    required this.category,
    required this.rating,
  });
}
