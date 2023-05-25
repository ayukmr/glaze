#include <stdio.h>
#include <stdlib.h>

// struct aliases
typedef struct Node Node;
typedef struct List List;

// linked list
struct List {
    int _;
    int length;

    Node* head;
    Node* tail;
};

// individual nodes
struct Node {
    void* value;

    Node* prev;
    Node* next;
};

// get length of list
int listLength(List* list) {
    return list->length;
}

// create new list
List listCreate() {
    List list;
    list.head = NULL;

    return list;
}

// prepend node to list
void listPrepend(List* list, void* value) {
    Node* node;

    if (list->head) {
        node = malloc(sizeof(Node));

        // set value of node
        node->value = value;
        node->next  = list->head;

        list->head = node;
        list->length += 1;
    } else {
        list->head = malloc(sizeof(Node));

        // set value of head
        (list->head)->value = value;
        list->tail = list->head;

        list->length = 1;
    }
}

// append node to list
void listAppend(List* list, void* value) {
    Node* node;

    if (list->head) {
        node = malloc(sizeof(Node));

        // set value of node
        node->value = value;
        node->prev  = list->tail;

        (list->tail)->next = node;
        list->tail = node;

        list->length += 1;
    } else {
        list->head = malloc(sizeof(Node));

        // set value of head
        (list->head)->value = value;
        list->tail = list->head;

        list->length = 1;
    }
}

// create list from range
List listRange(int start, int end) {
    int i;
    List list;

    list = listCreate();

    // append indexes
    for (i = start; i < end; i++) {
        listAppend(&list, (void*) i);
    }

    return list;
}

// get index in list
Node* listNode(List* list, int index) {
    int i;

    // use list head as current node
    Node* curNode = list->head;

    for (i = 0; i < index; i++) {
        // change current node to next node
        curNode = curNode->next;
    }

    return curNode;
}

// get index in list
void* listValue(List* list, int index) {
    return listNode(list, index)->value;
}

// set index in list
void listSet(List* list, int index, void* value) {
    listNode(list, index)->value = value;
}

// delete index in list
void listDelete(List* list, int index) {
    Node* node;

    if (index == 0) {
        node = (list->head)->next;

        // set new head
        list->head = node;
    } else {
        // remove node
        node = listNode(list, index);
        (node->prev)->next = node->next;
    }

    list->length -= 1;
}
