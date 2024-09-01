//
//  Created by ktiays on 2024/9/1.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#import <atomic>
#import <cctype>
#import <filesystem>
#import <format>
#import <fstream>
#import <iostream>
#import <sstream>
#import <stack>
#import <unordered_map>
#import <vector>

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "objc-encodingparser/parser.h"
#import "objc_dump_class.h"

extern "C" const char *dyld_image_path_containing_address(const void *address);

struct _objc_class {
    Class isa;
    Class superclass;

    std::atomic<uintptr_t> _bucketsAndMaybeMask;
    std::atomic<uint32_t> _maybeMask;
    uint16_t _flags;
    uint16_t _occupied;

    uintptr_t bits;
};

uintptr_t _class_getClassBits(Class aClass) {
    return ((_objc_class *) (__bridge const void *) aClass)->bits;
}

template <typename Sequence, typename Separator>
static std::string join(const Sequence &seq, const Separator &sep) {
    std::stringstream ss;
    for (const auto &s : seq) {
        if (&s != &seq.front())
            ss << sep;
        ss << s;
    }
    return ss.str();
}

static void rtrim(std::string &s) {
    s.erase(s.find_last_not_of(" \t\n\r\f\v") + 1);
}

#define UNKNOWN_TYPE_NAME "?"

struct __NodeVisitState {
public:
    bool skip_current_level;

    __NodeVisitState() : skip_current_level(false) {}

    std::vector<std::string> codable_types() const {
        return children_;
    }

    void append_child(std::string &&arg) {
        assert(!is_compound());
        children_.push_back(arg);
    }

    void append_comp(std::string &&ptr_name) {
        comps_.push(ptr_name);
    }

    std::string compound_name(const std::string &content_type) {
        std::stringstream content_stream;
        content_stream << content_type;

        while (!comps_.empty()) {
            content_stream << " " << comps_.top();
            comps_.pop();
        }

        return content_stream.str();
    }

    bool is_compound() const {
        return !comps_.empty();
    }

private:
    std::vector<std::string> children_;
    std::stack<std::string> comps_;
};

static void __visit_ocep_type_node(ocep_type_node_t node, int num, int depth, void *userdata) {
    if (depth == 0) {
        // The root node is empty, skip it.
        return;
    }

    static std::unordered_map<int, std::string> type_map = {
        {            OBJC_TYPE_OBJECT,                 "id"},
        {             OBJC_TYPE_CLASS,              "Class"},
        {               OBJC_TYPE_SEL,                "SEL"},
        {              OBJC_TYPE_CHAR,               "char"},
        {     OBJC_TYPE_UNSIGNED_CHAR,      "unsigned char"},
        {             OBJC_TYPE_SHORT,              "short"},
        {    OBJC_TYPE_UNSIGNED_SHORT,     "unsigned short"},
        {               OBJC_TYPE_INT,                "int"},
        {      OBJC_TYPE_UNSIGNED_INT,       "unsigned int"},
        {              OBJC_TYPE_LONG,               "long"},
        {     OBJC_TYPE_UNSIGNED_LONG,      "unsigned long"},
        {         OBJC_TYPE_LONG_LONG,          "long long"},
        {OBJC_TYPE_UNSIGNED_LONG_LONG, "unsigned long long"},
        {             OBJC_TYPE_FLOAT,              "float"},
        {            OBJC_TYPE_DOUBLE,             "double"},
        {         OBJC_TYPE_BIT_FIELD,                "bit"},
        {              OBJC_TYPE_BOOL,               "bool"},
        {              OBJC_TYPE_VOID,               "void"},
        {           OBJC_TYPE_UNKNOWN,    UNKNOWN_TYPE_NAME},
        {            OBJC_TYPE_STRING,             "char *"},
    };

    auto state = static_cast<__NodeVisitState *>(userdata);
    if (depth > 1 && state->skip_current_level) {
        return;
    } else {
        state->skip_current_level = false;
    }

    const auto type = node->type;

    const auto modifiers = node->modifiers;
    std::stringstream modifier_stream;
    // These modifiers are added as type prefixes.
    if (modifiers & OBJC_MODIFIER_ONEWAY) {
        modifier_stream << "oneway ";
    } else if (modifiers & OBJC_MODIFIER_IN) {
        modifier_stream << "in ";
    } else if (modifiers & OBJC_MODIFIER_OUT) {
        modifier_stream << "out ";
    } else if (modifiers & OBJC_MODIFIER_INOUT) {
        modifier_stream << "inout ";
    }

    std::string type_name;
    auto iter = type_map.find(type);
    if (iter != type_map.end()) {
        type_name = iter->second;
    } else {
        // The structure or union type is not in the type map.
        // Use the name of the node.
        auto name = node->name;
        if (name != nullptr) {
            type_name = name;
        }
    }

    switch (type) {
    case OBJC_TYPE_POINTER: {
        std::stringstream ptr_stream;
        ptr_stream << "*";

        if (modifiers & OBJC_MODIFIER_CONST) {
            // The `const` modifier is added as a suffix to the type.
            ptr_stream << " const";
        }

        state->append_comp(ptr_stream.str());
        return;
    }
    case OBJC_TYPE_ARRAY: {
        state->append_comp("[]");
        return;
    }
    case OBJC_TYPE_STRUCT:
    case OBJC_TYPE_UNION:
        state->skip_current_level = true;
    default:
        break;
    }

    if (type_name.empty()) {
        // Unable to resolve type name belongs to unexpected behavior.
        type_name = UNKNOWN_TYPE_NAME;
        assert(false);
    }

    if (state->is_compound()) {
        type_name = state->compound_name(type_name);
    }
    type_name = modifier_stream.str() + type_name;

    state->append_child(std::move(type_name));
}

static uint __p2uint(const char *num) {
    uint value = 0;
    while (*num && std::isdigit(*num)) {
        value = value * 10 + *num++ - '0';
    }
    return value;
}

static std::string var_codable_type(const std::string &type_encoding, uint *bits) {
    if (type_encoding.empty()) {
        return UNKNOWN_TYPE_NAME;
    }

    const auto front = type_encoding.front();
    switch (front) {
    case _C_ID:
        if (type_encoding.size() < 3) {
            return "id";
        } else {
            const auto name = std::string(type_encoding.begin() + 2, type_encoding.end() - 1);
            if (name.size() >= 2 && name.front() == '<' && name.back() == '>') {
                return "id" + name;
            } else {
                return name + " *";
            }
        }
        break;
    case _C_BFLD: {
        // The structure of the bit field is quite special but relatively simple,
        // so direct alignment makes it easier to handle and more efficient.
        if (bits != nullptr) {
            *bits = __p2uint(type_encoding.data() + 1);
        }
        return "unsigned int";
    }
    default:
        break;
    }

    auto root = ocep_parse_encoding(type_encoding.data());
    auto state = __NodeVisitState();
    ocep_type_node_traverse(root, &state, __visit_ocep_type_node);
    auto types = state.codable_types();
    assert(!types.empty());
    return types.front();
}

static std::string substring_to(const char **p, const char c) {
    auto ptr = *p;
    auto begin = ptr;
    while (*ptr != c && *ptr != '\0') {
        ++ptr;
    }
    *p = ptr;
    return std::string(begin, ptr);
}

#define _ATTR_TYPE_MARK 'T'
#define _ATTR_READONLY 'R'
#define _ATTR_COPY 'C'
#define _ATTR_RETAIN '&'
#define _ATTR_NONATOMIC 'N'
#define _ATTR_WEAK 'W'
#define _ATTR_VARIABLE 'V'
#define _ATTR_GETTER 'G'
#define _ATTR_SETTER 'S'

static std::string property_codable_def(objc_property_t property) {
    static std::unordered_map<char, std::string> attribute_map{
        { _ATTR_READONLY,  "readonly"},
        {     _ATTR_COPY,      "copy"},
        {   _ATTR_RETAIN,    "retain"},
        {_ATTR_NONATOMIC, "nonatomic"},
        {     _ATTR_WEAK,      "weak"},
        {   _ATTR_GETTER,    "getter"},
        {   _ATTR_SETTER,    "setter"},
    };

    std::string type_name = "void";
    std::vector<std::string> attributes;

    std::stringstream ss;
    ss << "@property ";

    const std::string encoded_attributes = property_getAttributes(property);
    for (auto ptr = encoded_attributes.data(); *ptr != '\0'; ++ptr) {
        auto attr = *(ptr++);
        switch (attr) {
        case _ATTR_TYPE_MARK: {
            type_name = var_codable_type(substring_to(&ptr, ','), nullptr);
        } break;
        case _ATTR_READONLY:
        case _ATTR_COPY:
        case _ATTR_RETAIN:
        case _ATTR_NONATOMIC: {
            attributes.push_back(attribute_map[attr]);
            substring_to(&ptr, ',');
        } break;
        case _ATTR_GETTER: {
            auto getter = substring_to(&ptr, ',');
            attributes.push_back(std::format("getter={}", getter));
        } break;
        case _ATTR_SETTER: {
            auto setter = substring_to(&ptr, ',');
            attributes.push_back(std::format("setter={}", setter));
        } break;
        case _ATTR_VARIABLE: {
            auto v = substring_to(&ptr, ',');
        } break;
        default:
            break;
        }
    }

    if (!attributes.empty()) {
        ss << "(" << join(attributes, ", ") << ") ";
    }
    ss << type_name << " " << property_getName(property) << ";";
    return ss.str();
}

static std::string method_codable_definition(Method method) {
    const auto typeEncoding = method_getTypeEncoding(method);
    auto node_root = ocep_parse_encoding(typeEncoding);
    auto state = __NodeVisitState();
    ocep_type_node_traverse(node_root, &state, __visit_ocep_type_node);

    const std::string selector = sel_getName(method_getName(method));
    const auto types = state.codable_types();
    const auto types_count = types.size();

    std::stringstream ss;
    assert(types_count >= 1);
    // The first type is the return type.
    ss << std::format("({})", types.front());
    // First two arguments in Objective-C are self and _cmd.
    // Skip them.
    int arg_index = 3;
    for (auto &c : selector) {
        ss << c;
        if (c == ':') {
            // Inserts the argument type and name into the selector.
            std::string type = arg_index < types_count ? types[arg_index++] : UNKNOWN_TYPE_NAME;
            ss << "(" << type << ")arg" << arg_index - 2 << ' ';
        }
    }
    auto result = ss.str();
    rtrim(result);
    return result;
}

extern "C" void objc_dump_classes(const char *target_directory) {
    int class_count;
    class_count = objc_getClassList(nullptr, 0);
    if (class_count > 0) {
        std::vector<__unsafe_unretained Class> classes;
        classes.resize(class_count);
        objc_getClassList(classes.data(), class_count);

        for (__unsafe_unretained auto clazz : classes) {
            objc_dump_class(clazz, target_directory);
        }
    }
}

extern "C" void objc_dump_class(Class aClass, const char *target_directory) {
    if (aClass == nil) {
        return;
    }
    const auto &class_name = class_getName(aClass);

    const auto class_bits = _class_getClassBits(aClass);
    if (class_bits & (1UL << 0) || class_bits & (1UL << 1)) {
        std::cout << "[-] Skip Swift class " << class_name << '\n';
        return;
    }

    // Get dylib path for class.
    const auto image_path = dyld_image_path_containing_address((__bridge void *) aClass);
    if (image_path == nullptr)
        return;

    NSString *libraryName = [[NSString stringWithUTF8String:image_path] lastPathComponent];

    // Create dylib directory if needed.
    std::filesystem::path framework_header_path(
        [[[NSString stringWithCString:target_directory encoding:NSUTF8StringEncoding] stringByAppendingPathComponent:libraryName] cStringUsingEncoding:NSUTF8StringEncoding]);
    if (!std::filesystem::exists(framework_header_path)) {
        if (!std::filesystem::create_directories(framework_header_path)) {
            return;
        }
    }

    std::cout << "[*] Processing " << class_name << '\n';

    std::ofstream header_file(framework_header_path.append(std::format("{}.h", class_name)).u8string());

    header_file << "//\n// Generated by ObjcRuntimeClassDump.\n//\n\n";

    header_file << std::format("@interface {}", class_name);
    id superclass = class_getSuperclass(aClass);
    if (superclass != nil) {
        header_file << std::format(" : {} ", class_getName(superclass));
    }

    uint protocol_count;
    const auto &protocols = class_copyProtocolList(aClass, &protocol_count);
    if (protocol_count > 0) {
        std::vector<std::string> protocols_list;
        for (uint i = 0; i < protocol_count; ++i) {
            const auto &protocol = protocols[i];
            const std::string protocol_name = protocol_getName(protocol);
            protocols_list.push_back(protocol_name);
        }
        header_file << std::format("<{}> ", join(protocols_list, ", "));
    }
    free(protocols);

    uint ivar_count;
    const auto &ivars = class_copyIvarList(aClass, &ivar_count);
    if (ivar_count > 0) {
        header_file << "{\n";
        for (uint i = 0; i < ivar_count; ++i) {
            const auto &ivar = ivars[i];
            auto typeEncoding = ivar_getTypeEncoding(ivar);
            if (typeEncoding == nullptr) {
                continue;
            }
            std::string encoded_type = typeEncoding;
            uint bits = 0;
            auto codable_type = encoded_type.empty() ? "?" : var_codable_type(encoded_type, &bits);
            header_file << std::format("\t{} {}", codable_type, ivar_getName(ivar));
            if (bits > 0) {
                header_file << " : " << bits;
            }
            header_file << ";\n";
        }
        header_file << "}";
    }
    free(ivars);
    header_file << "\n\n";

    uint property_count;
    const auto &properties = class_copyPropertyList(aClass, &property_count);
    if (property_count > 0) {
        for (uint i = 0; i < property_count; ++i) {
            header_file << std::format("{}\n", property_codable_def(properties[i]));
        }
        header_file << "\n";
    }
    free(properties);

    uint method_count;
    // Class method list.
    const auto &class_methods = class_copyMethodList(object_getClass((id) aClass), &method_count);
    if (method_count > 0) {
        for (uint i = 0; i < method_count; ++i) {
            const auto &method = class_methods[i];
            header_file << std::format("+ {};\n", method_codable_definition(method));
        }
        header_file << "\n";
    }
    free(class_methods);
    // Instance method list.
    const auto &instance_methods = class_copyMethodList(aClass, &method_count);
    if (method_count > 0) {
        for (uint i = 0; i < method_count; ++i) {
            const auto &method = instance_methods[i];
            header_file << std::format("- {};\n", method_codable_definition(method));
        }
        header_file << "\n";
    }
    free(instance_methods);

    header_file << "@end";
}
