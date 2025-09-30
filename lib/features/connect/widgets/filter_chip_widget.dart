// lib/features/connect/widgets/filter_chip_widget.dart
import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

class FilterChipWidget extends StatelessWidget {
  final String selectedFilter;
  final List<String> filterOptions;
  final Function(String) onFilterSelected;

  const FilterChipWidget({
    super.key,
    required this.selectedFilter,
    required this.filterOptions,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filterOptions.length,
        itemBuilder: (context, index) {
          final filter = filterOptions[index];
          final isSelected = selectedFilter == filter;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                onFilterSelected(selected ? filter : 'Semua');
              },
              backgroundColor: Colors.grey[200],
              selectedColor: MC.darkBrown,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : MC.darkBrown,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        },
      ),
    );
  }
}
