const Ajv = require('ajv');
const fs = require('fs');
const path = require('path');

// Load the schema
const schema = JSON.parse(fs.readFileSync('cli-command-schema.json', 'utf8'));

// Create AJV instance with meta-schema validation
const ajv = new Ajv({ 
    allErrors: true,
    strict: true,
    validateSchema: true 
});

console.log('🔍 Validating the schema itself...');

try {
    // Compile the schema (this validates it against JSON Schema meta-schema)
    const validate = ajv.compile(schema);
    console.log('✅ Schema is valid JSON Schema (draft-07)!');
    
    // Load and validate the example data
    console.log('\n🔍 Validating example data against schema...');
    const exampleData = JSON.parse(fs.readFileSync(path.join('..', 'example', 'configure.json'), 'utf8'));
    
    const valid = validate(exampleData);
    
    if (valid) {
        console.log('✅ Example data validation passed!');
        console.log('\n📊 Validation Summary:');
        console.log(`- Schema Title: ${schema.title}`);
        console.log(`- Required Properties: ${schema.required.join(', ')}`);
        console.log(`- Command Name: ${exampleData.Name}`);
        console.log(`- Total Options: ${exampleData.Options.length}`);
        
        // Count options by type/structure
        const optionsWithArgs = exampleData.Options.filter(opt => opt.Arguments && opt.Arguments.length > 0);
        const optionsWithShort = exampleData.Options.filter(opt => opt.Short && opt.Short.length > 0);
        const optionsWithAlias = exampleData.Options.filter(opt => opt.Alias && opt.Alias.length > 0);
        
        console.log(`- Options with arguments: ${optionsWithArgs.length}`);
        console.log(`- Options with short forms: ${optionsWithShort.length}`);
        console.log(`- Options with aliases: ${optionsWithAlias.length}`);
        
        // Show an example of a complex option
        const complexOption = exampleData.Options.find(opt => 
            (opt.Arguments && opt.Arguments.length > 0) && 
            (opt.Short && opt.Short.length > 0)
        );
        if (complexOption) {
            console.log('\n📝 Example complex option:');
            console.log(`- Name: ${complexOption.Name}`);
            if (complexOption.Short) console.log(`- Short: ${complexOption.Short.join(', ')}`);
            if (complexOption.Alias) console.log(`- Alias: ${complexOption.Alias.join(', ')}`);
            if (complexOption.Arguments) console.log(`- Arguments: ${complexOption.Arguments.join(', ')}`);
            console.log(`- Description: ${complexOption.Description.substring(0, 80)}...`);
        }
        
    } else {
        console.log('❌ Example data validation failed!');
        console.log('Validation errors:');
        validate.errors.forEach(error => {
            console.log(`- ${error.instancePath}: ${error.message}`);
            if (error.data) {
                console.log(`  Data: ${JSON.stringify(error.data)}`);
            }
        });
    }
    
} catch (error) {
    console.log('❌ Schema compilation failed!');
    console.log('Error:', error.message);
    
    if (error.errors) {
        console.log('Schema validation errors:');
        error.errors.forEach(err => {
            console.log(`- ${err.instancePath}: ${err.message}`);
        });
    }
}