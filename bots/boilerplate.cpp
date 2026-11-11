#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

using namespace std;

/**
 * Auto-generated code below aims at helping you parse
 * the standard input according to the problem statement.
 **/

int main()
{

    // game loop
    while (1) {
        int my_ship_count; // the number of remaining ships
        cin >> my_ship_count; cin.ignore();
        int entity_count; // the number of entities (e.g. ships, mines or cannonballs)
        cin >> entity_count; cin.ignore();
        for (int i = 0; i < entity_count; i++) {
            int entity_id;
            string entity_type;
            int x;
            int y;
            int arg1;
            int arg2;
            int arg3;
            int arg4;
            cin >> entity_id >> entity_type >> x >> y >> arg1 >> arg2 >> arg3 >> arg4; cin.ignore();
        }
        for (int i = 0; i < my_ship_count; i++) {

            // Write an action using cout. DON'T FORGET THE "<< endl"
            // To debug: cerr << "Debug messages..." << endl;

            cout << "MOVE 11 10" << endl; // Any valid action, such as "WAIT" or "MOVE x y"
        }
    }
}