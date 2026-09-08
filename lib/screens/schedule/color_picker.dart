part of 'screen_schedule.dart';

List<Color> _colorCollection = [
  const Color(0xFF0F8644),
  const Color(0xFF8B1FA9),
  const Color(0xFFD20100),
  const Color(0xFFFC571D),
  const Color(0xFF85461E),
  const Color(0xFFFF00FF),
  const Color(0xFF3D4FB5),
  const Color(0xFFE47C73),
  const Color(0xFF636363),
];

List<String> _colorNames = <String>[
  'Green',
  'Purple',
  'Red',
  'Orange',
  'Caramel',
  'Magenta',
  'Blue',
  'Peach',
  'Gray',
];

// Define the color picker widget.
class _ColorPicker extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _ColorPickerState();
  }
}

// Define the color picker state.
class _ColorPickerState extends State<_ColorPicker> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: double.maxFinite,
        // Set the width of the SizedBox to the maximum possible value
        child: ListView.builder(
          padding: const EdgeInsets.all(0),
          // Remove the default padding of the ListView
          itemCount: _colorCollection.length - 1,
          // Set the number of items in the ListView based on the color collection length
          itemBuilder: (BuildContext context, int index) {
            return ListTile(
              contentPadding: const EdgeInsets.all(0),
              // Remove the default padding of the ListTile
              leading: Icon(
                index == _selectedColorIndex
                    ? Icons
                        .lens // If the current index matches the selected color index, show the 'lens' icon
                    : Icons.trip_origin,
                // Otherwise, show the 'trip_origin' icon
                color: _colorCollection[
                    index], // Set the icon color based on the color collection
              ),
              title: Text(_colorNames[index]),
              // Set the title of the ListTile based on the color names collection
              onTap: () {
                setState(() {
                  _selectedColorIndex =
                      index; // Update the selected color index when the ListTile is tapped
                });
                Future.delayed(const Duration(milliseconds: 200), () {
                  // After a delay of 200 milliseconds
                  if (context.mounted) {
                    Navigator.pop(context); // Close the dialog
                  }
                });
              },
            );
          },
        ),
      ),
    );
  }
}
